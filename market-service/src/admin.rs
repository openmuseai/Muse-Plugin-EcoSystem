use super::*;

#[derive(Template)]
#[template(path = "admin.html")]
struct AdminTemplate;

pub async fn page() -> Html<String> {
    Html(AdminTemplate.render().expect("admin template"))
}

pub async fn css() -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/css; charset=utf-8")],
        include_str!("../assets/admin.css"),
    )
}

pub async fn js() -> impl IntoResponse {
    (
        [(
            header::CONTENT_TYPE,
            "application/javascript; charset=utf-8",
        )],
        include_str!("../assets/admin.js"),
    )
}

pub async fn submissions(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> ApiResult<Json<Value>> {
    authorize(&headers, &state.reviewer_token)?;
    let rows = sqlx::query("SELECT id,name,version,document,digest,state,developer_subject,review_note,created_at,updated_at FROM market_versions ORDER BY created_at DESC")
        .fetch_all(&state.db).await.map_err(internal)?;
    let mut items = Vec::new();
    for row in rows {
        let document: String = row.try_get("document").map_err(internal)?;
        items.push(json!({
            "id": row.try_get::<String,_>("id").map_err(internal)?,
            "name": row.try_get::<String,_>("name").map_err(internal)?,
            "version": row.try_get::<String,_>("version").map_err(internal)?,
            "document": serde_json::from_str::<Value>(&document).map_err(internal)?,
            "digest": row.try_get::<String,_>("digest").map_err(internal)?,
            "state": row.try_get::<String,_>("state").map_err(internal)?,
            "developer": row.try_get::<String,_>("developer_subject").map_err(internal)?,
            "reviewNote": row.try_get::<String,_>("review_note").map_err(internal)?,
            "createdAt": row.try_get::<i64,_>("created_at").map_err(internal)?,
            "updatedAt": row.try_get::<i64,_>("updated_at").map_err(internal)?,
        }));
    }
    Ok(Json(json!({"submissions": items})))
}

#[derive(Deserialize)]
pub struct Review {
    note: Option<String>,
}

pub async fn transition(
    State(state): State<Arc<AppState>>,
    UrlPath((id, action)): UrlPath<(String, String)>,
    headers: HeaderMap,
    Json(review): Json<Review>,
) -> ApiResult<Json<Value>> {
    authorize(&headers, &state.reviewer_token)?;
    let (expected, next) = match action.as_str() {
        "approve" => ("pending", "approved"),
        "reject" => ("pending", "rejected"),
        "delist" => ("approved", "delisted"),
        "relist" => ("delisted", "approved"),
        _ => return Err(bad("Unknown review action")),
    };
    let note = review.note.unwrap_or_default();
    if note.len() > 2000 || ((action == "reject" || action == "delist") && note.trim().is_empty()) {
        return Err(bad("A short review reason is required"));
    }
    let mut transaction = state.db.begin().await.map_err(internal)?;
    let result = sqlx::query(
        "UPDATE market_versions SET state=$1,review_note=$2,updated_at=$3 WHERE id=$4 AND state=$5",
    )
    .bind(next)
    .bind(&note)
    .bind(now())
    .bind(&id)
    .bind(expected)
    .execute(&mut *transaction)
    .await
    .map_err(internal)?;
    if result.rows_affected() != 1 {
        return Err(ApiError(
            StatusCode::CONFLICT,
            "Submission state changed or not found".into(),
        ));
    }
    sqlx::query("INSERT INTO market_audit (id,submission_id,action,actor,note,created_at) VALUES ($1,$2,$3,'reviewer',$4,$5)")
        .bind(Uuid::new_v4().to_string()).bind(&id).bind(&action).bind(&note).bind(now())
        .execute(&mut *transaction).await.map_err(internal)?;
    transaction.commit().await.map_err(internal)?;
    Ok(Json(json!({"id": id, "state": next})))
}

pub async fn audit_log(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
) -> ApiResult<Json<Value>> {
    authorize(&headers, &state.reviewer_token)?;
    let rows = sqlx::query("SELECT submission_id,action,actor,note,created_at FROM market_audit ORDER BY created_at DESC LIMIT 100")
        .fetch_all(&state.db).await.map_err(internal)?;
    let mut events = Vec::new();
    for row in rows {
        events.push(json!({
            "submissionId": row.try_get::<String,_>("submission_id").map_err(internal)?,
            "action": row.try_get::<String,_>("action").map_err(internal)?,
            "actor": row.try_get::<String,_>("actor").map_err(internal)?,
            "note": row.try_get::<String,_>("note").map_err(internal)?,
            "createdAt": row.try_get::<i64,_>("created_at").map_err(internal)?,
        }));
    }
    Ok(Json(json!({"events": events})))
}
