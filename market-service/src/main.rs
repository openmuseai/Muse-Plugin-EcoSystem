use anyhow::{Context, Result};
use askama::Template;
use axum::{
    body::Bytes,
    extract::{DefaultBodyLimit, Path as UrlPath, Query, State},
    http::{header, HeaderMap, StatusCode},
    response::{Html, IntoResponse, Response},
    routing::{get, post, put},
    Json, Router,
};
use semver::Version;
use serde::Deserialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use sqlx::{any::AnyPoolOptions, AnyPool, Row};
use std::{
    collections::{BTreeMap, HashSet},
    env,
    io::Read,
    path::PathBuf,
    sync::Arc,
};
use tokio::net::TcpListener;
use uuid::Uuid;

const MAX_PACKAGE: usize = 80 * 1024 * 1024;
const MAX_EXPANDED: u64 = 160 * 1024 * 1024;

#[derive(Clone)]
struct AppState {
    db: AnyPool,
    storage: ArtifactStorage,
    developer_token: String,
    reviewer_token: String,
    developer_namespace: Option<String>,
    origin: String,
    redis: Option<redis::aio::ConnectionManager>,
}

#[derive(Clone)]
enum ArtifactStorage {
    Files(PathBuf),
    #[cfg(feature = "s3")]
    S3 {
        client: aws_sdk_s3::Client,
        bucket: String,
    },
}

impl ArtifactStorage {
    async fn put(&self, digest: &str, bytes: &[u8]) -> Result<()> {
        match self {
            Self::Files(root) => {
                tokio::fs::create_dir_all(root).await?;
                let target = root.join(format!("{digest}.mcpb"));
                if tokio::fs::try_exists(&target).await? {
                    return Ok(());
                }
                let temporary = root.join(format!(".{digest}-{}", Uuid::new_v4()));
                tokio::fs::write(&temporary, bytes).await?;
                tokio::fs::rename(temporary, target).await?;
            }
            #[cfg(feature = "s3")]
            Self::S3 { client, bucket } => {
                client
                    .put_object()
                    .bucket(bucket)
                    .key(format!("packages/{digest}.mcpb"))
                    .body(aws_sdk_s3::primitives::ByteStream::from(bytes.to_vec()))
                    .send()
                    .await?;
            }
        }
        Ok(())
    }

    async fn get(&self, digest: &str) -> Result<Vec<u8>> {
        match self {
            Self::Files(root) => Ok(tokio::fs::read(root.join(format!("{digest}.mcpb"))).await?),
            #[cfg(feature = "s3")]
            Self::S3 { client, bucket } => {
                let object = client
                    .get_object()
                    .bucket(bucket)
                    .key(format!("packages/{digest}.mcpb"))
                    .send()
                    .await?;
                Ok(object.body.collect().await?.into_bytes().to_vec())
            }
        }
    }
}

#[derive(Debug)]
struct ApiError(StatusCode, String);

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        (self.0, Json(json!({"error": self.1}))).into_response()
    }
}

type ApiResult<T> = std::result::Result<T, ApiError>;

fn bad(message: impl Into<String>) -> ApiError {
    ApiError(StatusCode::BAD_REQUEST, message.into())
}

fn internal(error: impl std::fmt::Display) -> ApiError {
    tracing::error!("market failure: {error}");
    ApiError(
        StatusCode::INTERNAL_SERVER_ERROR,
        "Internal service error".into(),
    )
}

fn authorize(headers: &HeaderMap, token: &str) -> ApiResult<()> {
    let header = headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok());
    if header == Some(&format!("Bearer {token}")) {
        Ok(())
    } else {
        Err(ApiError(
            StatusCode::UNAUTHORIZED,
            "Bearer token required".into(),
        ))
    }
}

fn digest_ok(digest: &str) -> bool {
    digest.len() == 64
        && digest
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() && !byte.is_ascii_uppercase())
}

fn verify_bundle(bytes: &[u8]) -> ApiResult<Value> {
    let mut archive =
        zip::ZipArchive::new(std::io::Cursor::new(bytes)).map_err(|_| bad("Invalid MCPB ZIP"))?;
    if archive.len() == 0 || archive.len() > 1024 {
        return Err(bad("Invalid MCPB file count"));
    }
    let mut expanded = 0_u64;
    let mut names = HashSet::new();
    for index in 0..archive.len() {
        let file = archive
            .by_index(index)
            .map_err(|_| bad("Invalid MCPB entry"))?;
        let name = file.name().to_string();
        if name.starts_with('/')
            || name.contains('\\')
            || name.split('/').any(|part| part == ".." || part.is_empty())
        {
            return Err(bad("Unsafe MCPB path"));
        }
        if !names.insert(name.clone()) {
            return Err(bad("Duplicate MCPB path"));
        }
        if file
            .unix_mode()
            .is_some_and(|mode| mode & 0o170000 == 0o120000)
        {
            return Err(bad("MCPB symbolic links are unsupported"));
        }
        expanded = expanded
            .checked_add(file.size())
            .ok_or_else(|| bad("MCPB expanded size overflow"))?;
        if expanded > MAX_EXPANDED {
            return Err(bad("MCPB expanded size exceeded"));
        }
    }
    let mut manifest_text = String::new();
    archive
        .by_name("manifest.json")
        .map_err(|_| bad("MCPB manifest missing"))?
        .take(64 * 1024)
        .read_to_string(&mut manifest_text)
        .map_err(|_| bad("Invalid MCPB manifest"))?;
    let manifest: Value =
        serde_json::from_str(&manifest_text).map_err(|_| bad("Invalid MCPB manifest JSON"))?;
    let entry = manifest
        .pointer("/server/entry_point")
        .and_then(Value::as_str)
        .ok_or_else(|| bad("MCPB server entry point missing"))?;
    if !["0.3", "0.4"].contains(&manifest["manifest_version"].as_str().unwrap_or(""))
        || manifest.pointer("/server/type").and_then(Value::as_str) != Some("node")
        || !names.contains(entry)
    {
        return Err(bad("Unsupported MCPB manifest"));
    }
    Ok(manifest)
}

async fn migrate(db: &AnyPool) -> Result<()> {
    for statement in [
        "CREATE TABLE IF NOT EXISTS uploaded_packages (digest TEXT PRIMARY KEY, size BIGINT NOT NULL, uploaded_at BIGINT NOT NULL)",
        "CREATE TABLE IF NOT EXISTS market_versions (id TEXT PRIMARY KEY, name TEXT NOT NULL, version TEXT NOT NULL, document TEXT NOT NULL, digest TEXT NOT NULL, state TEXT NOT NULL, developer_subject TEXT NOT NULL, review_note TEXT NOT NULL DEFAULT '', created_at BIGINT NOT NULL, updated_at BIGINT NOT NULL, UNIQUE(name, version))",
        "CREATE INDEX IF NOT EXISTS market_versions_state_name ON market_versions(state, name)",
        "CREATE TABLE IF NOT EXISTS market_audit (id TEXT PRIMARY KEY, submission_id TEXT NOT NULL, action TEXT NOT NULL, actor TEXT NOT NULL, note TEXT NOT NULL, created_at BIGINT NOT NULL)",
    ] {
        sqlx::query(statement).execute(db).await?;
    }
    Ok(())
}

fn now() -> i64 {
    chrono::Utc::now().timestamp()
}

async fn rate_limit(state: &AppState, action: &str, maximum: i64) -> ApiResult<()> {
    let Some(manager) = &state.redis else {
        return Ok(());
    };
    let key = format!("market:limit:{action}:{}", now() / 60);
    let mut connection = manager.clone();
    let count: i64 = redis::cmd("INCR")
        .arg(&key)
        .query_async(&mut connection)
        .await
        .map_err(internal)?;
    if count == 1 {
        let _: bool = redis::cmd("EXPIRE")
            .arg(&key)
            .arg(120)
            .query_async(&mut connection)
            .await
            .map_err(internal)?;
    }
    if count > maximum {
        return Err(ApiError(
            StatusCode::TOO_MANY_REQUESTS,
            "Rate limit exceeded".into(),
        ));
    }
    Ok(())
}

async fn upload_package(
    State(state): State<Arc<AppState>>,
    UrlPath(file): UrlPath<String>,
    headers: HeaderMap,
    body: Bytes,
) -> ApiResult<(StatusCode, Json<Value>)> {
    authorize(&headers, &state.developer_token)?;
    rate_limit(&state, "upload", 30).await?;
    let digest = file
        .strip_suffix(".mcpb")
        .ok_or_else(|| bad("Expected MCPB package"))?;
    if !digest_ok(digest) || body.len() > MAX_PACKAGE {
        return Err(bad("Invalid package digest or size"));
    }
    let actual = hex::encode(Sha256::digest(&body));
    if actual != digest {
        return Err(bad("SHA-256 mismatch"));
    }
    verify_bundle(&body)?;
    state.storage.put(digest, &body).await.map_err(internal)?;
    sqlx::query("INSERT INTO uploaded_packages (digest,size,uploaded_at) VALUES ($1,$2,$3) ON CONFLICT (digest) DO NOTHING")
        .bind(digest).bind(body.len() as i64).bind(now()).execute(&state.db).await.map_err(internal)?;
    Ok((
        StatusCode::CREATED,
        Json(json!({"digest": format!("sha256:{digest}")})),
    ))
}

fn validate_document(state: &AppState, document: &Value) -> ApiResult<(String, String, String)> {
    let name = document["name"]
        .as_str()
        .ok_or_else(|| bad("Registry name required"))?;
    let (namespace, leaf) = name
        .split_once('/')
        .ok_or_else(|| bad("Registry name needs namespace/name"))?;
    if namespace.is_empty()
        || leaf.is_empty()
        || leaf.contains('/')
        || !name
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b"-._/".contains(&b))
    {
        return Err(bad("Invalid MCP Registry name"));
    }
    if state
        .developer_namespace
        .as_deref()
        .is_some_and(|owned| owned != namespace)
    {
        return Err(ApiError(
            StatusCode::FORBIDDEN,
            "Developer does not own namespace".into(),
        ));
    }
    let version = document["version"]
        .as_str()
        .ok_or_else(|| bad("Version required"))?;
    Version::parse(version).map_err(|_| bad("Exact semantic version required"))?;
    if !document["description"].is_string() {
        return Err(bad("Description required"));
    }
    let packages = document["packages"]
        .as_array()
        .ok_or_else(|| bad("MCPB package required"))?;
    if packages.len() != 1 {
        return Err(bad("Exactly one MCPB package required"));
    }
    let package = &packages[0];
    let digest = package["fileSha256"]
        .as_str()
        .ok_or_else(|| bad("Package digest required"))?;
    if !digest_ok(digest)
        || package["registryType"] != "mcpb"
        || package["transport"]["type"] != "stdio"
        || package["identifier"] != format!("{}/packages/{digest}.mcpb", state.origin)
    {
        return Err(bad("Invalid standard MCPB descriptor"));
    }
    if let Some(remotes) = document.get("remotes") {
        let remotes = remotes
            .as_array()
            .ok_or_else(|| bad("Invalid remote endpoint list"))?;
        for remote in remotes {
            let url = remote["url"]
                .as_str()
                .ok_or_else(|| bad("Remote URL required"))?;
            let uri: axum::http::Uri = url.parse().map_err(|_| bad("Invalid remote URL"))?;
            let local = uri.scheme_str() == Some("http")
                && matches!(uri.host(), Some("127.0.0.1" | "localhost"));
            let registry_is_local = state.origin.starts_with("http://127.0.0.1:")
                || state.origin.starts_with("http://localhost:");
            if remote["type"] != "streamable-http"
                || !(uri.scheme_str() == Some("https") || (registry_is_local && local))
            {
                return Err(bad("Remote must use MCP Streamable HTTP over HTTPS"));
            }
        }
    }
    Ok((name.into(), version.into(), digest.into()))
}

async fn publish(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Json(document): Json<Value>,
) -> ApiResult<(StatusCode, Json<Value>)> {
    authorize(&headers, &state.developer_token)?;
    rate_limit(&state, "publish", 60).await?;
    let (name, version, digest) = validate_document(&state, &document)?;
    let uploaded = sqlx::query("SELECT digest FROM uploaded_packages WHERE digest=$1")
        .bind(&digest)
        .fetch_optional(&state.db)
        .await
        .map_err(internal)?;
    if uploaded.is_none() {
        return Err(bad("Upload package first"));
    }
    let bytes = state.storage.get(&digest).await.map_err(internal)?;
    let manifest = verify_bundle(&bytes)?;
    if manifest["version"] != version {
        return Err(bad("Bundle version differs from registry version"));
    }
    if manifest["name"] != name.split_once('/').map(|(_, leaf)| leaf).unwrap_or("") {
        return Err(bad("Bundle name differs from registry name"));
    }
    let id = Uuid::new_v4().to_string();
    let mut transaction = state.db.begin().await.map_err(internal)?;
    let inserted = sqlx::query("INSERT INTO market_versions (id,name,version,document,digest,state,developer_subject,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,'pending','dev-token',$6,$7)")
        .bind(&id).bind(&name).bind(&version).bind(document.to_string()).bind(&digest).bind(now()).bind(now())
        .execute(&mut *transaction).await;
    if let Err(error) = inserted {
        if error
            .as_database_error()
            .is_some_and(|database| database.is_unique_violation())
        {
            return Err(ApiError(
                StatusCode::CONFLICT,
                "Version already submitted".into(),
            ));
        }
        return Err(internal(error));
    }
    sqlx::query("INSERT INTO market_audit (id,submission_id,action,actor,note,created_at) VALUES ($1,$2,'submitted','dev-token','',$3)")
        .bind(Uuid::new_v4().to_string()).bind(&id).bind(now())
        .execute(&mut *transaction).await.map_err(internal)?;
    transaction.commit().await.map_err(internal)?;
    Ok((
        StatusCode::ACCEPTED,
        Json(json!({
            "server": document,
            "_meta": {"status": "pending", "submissionId": id}
        })),
    ))
}

#[derive(Deserialize)]
struct CatalogQuery {
    search: Option<String>,
    cursor: Option<String>,
}

async fn catalog(
    State(state): State<Arc<AppState>>,
    Query(query): Query<CatalogQuery>,
) -> ApiResult<Json<Value>> {
    let cursor = query
        .cursor
        .as_deref()
        .unwrap_or("0")
        .parse::<usize>()
        .map_err(|_| bad("Invalid cursor"))?;
    let rows =
        sqlx::query("SELECT name,version,document FROM market_versions WHERE state='approved'")
            .fetch_all(&state.db)
            .await
            .map_err(internal)?;
    let mut latest: BTreeMap<String, (Version, Value)> = BTreeMap::new();
    for row in rows {
        let name: String = row.try_get("name").map_err(internal)?;
        let version: String = row.try_get("version").map_err(internal)?;
        let raw: String = row.try_get("document").map_err(internal)?;
        let parsed = Version::parse(&version).map_err(internal)?;
        if latest.get(&name).is_none_or(|(old, _)| parsed > *old) {
            latest.insert(
                name,
                (parsed, serde_json::from_str(&raw).map_err(internal)?),
            );
        }
    }
    let search = query.search.unwrap_or_default().to_lowercase();
    let documents: Vec<Value> = latest
        .into_iter()
        .filter_map(|(name, (_, mut document))| {
            let description = document["description"].as_str().unwrap_or("");
            if !search.is_empty()
                && !format!("{name} {description}")
                    .to_lowercase()
                    .contains(&search)
            {
                None
            } else {
                // The registry owns package URLs. Rebuild the standard descriptor
                // when its public origin changes without mutating the reviewed record.
                if let Some(digest) = document["packages"][0]["fileSha256"].as_str() {
                    document["packages"][0]["identifier"] =
                        json!(format!("{}/packages/{digest}.mcpb", state.origin));
                }
                Some(document)
            }
        })
        .collect();
    let servers: Vec<Value> = documents
        .iter()
        .skip(cursor)
        .take(50)
        .map(|document| {
            json!({
                "server": document, "_meta": {"status": "active", "isLatest": true}
            })
        })
        .collect();
    let metadata = if cursor.saturating_add(50) < documents.len() {
        json!({"nextCursor": (cursor + 50).to_string()})
    } else {
        json!({})
    };
    Ok(Json(json!({"servers": servers, "metadata": metadata})))
}

async fn package_download(
    State(state): State<Arc<AppState>>,
    UrlPath(file): UrlPath<String>,
) -> ApiResult<Response> {
    let digest = file
        .strip_suffix(".mcpb")
        .ok_or_else(|| bad("Expected MCPB package"))?;
    if !digest_ok(digest) {
        return Err(bad("Invalid package digest"));
    }
    let row =
        sqlx::query("SELECT id FROM market_versions WHERE digest=$1 AND state='approved' LIMIT 1")
            .bind(digest)
            .fetch_optional(&state.db)
            .await
            .map_err(internal)?;
    if row.is_none() {
        return Err(ApiError(
            StatusCode::NOT_FOUND,
            "Package not published".into(),
        ));
    }
    let bytes = state.storage.get(digest).await.map_err(internal)?;
    Ok((
        StatusCode::OK,
        [
            (header::CONTENT_TYPE, "application/octet-stream"),
            (header::CACHE_CONTROL, "private, no-store"),
        ],
        bytes,
    )
        .into_response())
}

mod admin;

async fn health() -> Json<Value> {
    Json(json!({"status":"ok","service":"muse-plugin-market"}))
}

fn router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/v0.1/servers", get(catalog))
        .route("/v0.1/publish", post(publish))
        .route("/v0.1/packages/:file", put(upload_package))
        .route("/packages/:file", put(upload_package))
        .route("/packages/:file", get(package_download))
        .route("/internal/submissions", get(admin::submissions))
        .route("/internal/submissions/:id/:action", post(admin::transition))
        .route("/internal/audit", get(admin::audit_log))
        .route("/admin", get(admin::page))
        .route("/admin/admin.css", get(admin::css))
        .route("/admin/admin.js", get(admin::js))
        .layer(DefaultBodyLimit::max(MAX_PACKAGE))
        .with_state(state)
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .json()
        .init();
    sqlx::any::install_default_drivers();
    let database_url =
        env::var("MARKET_DATABASE_URL").unwrap_or_else(|_| "sqlite://market.db?mode=rwc".into());
    let db = AnyPoolOptions::new()
        .max_connections(5)
        .connect(&database_url)
        .await
        .context("connect market database")?;
    migrate(&db).await.context("migrate market database")?;
    let storage = match env::var("MARKET_STORAGE_BACKEND")
        .unwrap_or_else(|_| "files".into())
        .as_str()
    {
        "files" => ArtifactStorage::Files(PathBuf::from(
            env::var("MARKET_STORAGE_DIR").unwrap_or_else(|_| "./data/packages".into()),
        )),
        #[cfg(feature = "s3")]
        "s3" => {
            let bucket = env::var("MARKET_S3_BUCKET").context("MARKET_S3_BUCKET required")?;
            let mut loader = aws_config::defaults(aws_config::BehaviorVersion::latest());
            if let Ok(endpoint) = env::var("MARKET_S3_ENDPOINT") {
                loader = loader.endpoint_url(endpoint);
            }
            let shared = loader.load().await;
            let config = aws_sdk_s3::config::Builder::from(&shared)
                .force_path_style(true)
                .build();
            let client = aws_sdk_s3::Client::from_conf(config);
            if env::var("MARKET_S3_AUTO_CREATE_BUCKET").as_deref() == Ok("true")
                && client.head_bucket().bucket(&bucket).send().await.is_err()
            {
                client
                    .create_bucket()
                    .bucket(&bucket)
                    .send()
                    .await
                    .context("create local market bucket")?;
            }
            ArtifactStorage::S3 { client, bucket }
        }
        other => anyhow::bail!("unsupported storage backend: {other}"),
    };
    let listen = env::var("MARKET_LISTEN").unwrap_or_else(|_| "127.0.0.1:8787".into());
    let origin = env::var("MARKET_PUBLIC_ORIGIN").unwrap_or_else(|_| format!("http://{listen}"));
    let developer_token =
        env::var("MARKET_DEVELOPER_TOKEN").context("MARKET_DEVELOPER_TOKEN required")?;
    let reviewer_token =
        env::var("MARKET_REVIEWER_TOKEN").context("MARKET_REVIEWER_TOKEN required")?;
    anyhow::ensure!(
        !developer_token.is_empty()
            && !reviewer_token.is_empty()
            && developer_token != reviewer_token,
        "developer and reviewer tokens must be distinct nonempty values"
    );
    let redis = if let Ok(url) = env::var("MARKET_REDIS_URL") {
        Some(
            redis::Client::open(url)?
                .get_connection_manager()
                .await
                .context("connect market Redis")?,
        )
    } else {
        None
    };
    let state = Arc::new(AppState {
        db,
        storage,
        developer_token,
        reviewer_token,
        developer_namespace: env::var("MARKET_DEVELOPER_NAMESPACE").ok(),
        origin: origin.trim_end_matches('/').into(),
        redis,
    });
    let listener = TcpListener::bind(&listen)
        .await
        .context("bind market listener")?;
    tracing::info!(%listen, "plugin market listening");
    axum::serve(listener, router(state)).await?;
    Ok(())
}
