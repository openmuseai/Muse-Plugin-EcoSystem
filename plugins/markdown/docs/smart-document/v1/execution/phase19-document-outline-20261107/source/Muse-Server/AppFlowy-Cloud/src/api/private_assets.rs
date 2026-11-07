//! Object-scoped private attachments over the existing Cloud bucket storage.
//! The namespace is reserved from all legacy public/multipart blob routes.
use access_control::act::Action;
use actix_web::{web, HttpRequest, HttpResponse, Result, Scope};
use app_error::AppError;
use aws_sdk_s3::primitives::ByteStream;
use futures_util::TryStreamExt;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::api::file_storage::{get_blob_by_object_key, BlobPathV1};
use crate::biz::{authentication::jwt::UserUuid, guest};
use crate::state::AppState;

pub const PRIVATE_PREFIX: &str = "muse-private-object-";
const MAX_ASSET_BYTES: usize = 12 * 1024 * 1024;

pub fn is_private_asset_path(path: &str) -> bool {
  path
    .split('/')
    .any(|segment| segment.starts_with(PRIVATE_PREFIX))
}

pub fn deny_public_private_asset(path: &str) -> std::result::Result<(), AppError> {
  if is_private_asset_path(path) {
    return Err(AppError::RecordNotFound("Not found".into()));
  }
  Ok(())
}

pub fn private_assets_scope() -> Scope {
  web::scope("/{workspace_id}/private/{object_id}").service(
    web::resource("/blob/{asset_id}")
      .app_data(web::PayloadConfig::new(MAX_ASSET_BYTES))
      .route(web::put().to(put_private_asset))
      .route(web::get().to(get_private_asset)),
  )
}

#[derive(Deserialize)]
struct AssetPath {
  workspace_id: Uuid,
  object_id: Uuid,
  asset_id: String,
}

impl AssetPath {
  fn key(&self) -> std::result::Result<BlobPathV1, AppError> {
    if self.asset_id.len() != 64
      || !self
        .asset_id
        .bytes()
        .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
      return Err(AppError::InvalidRequest(
        "asset_id must be a SHA-256 hex digest".into(),
      ));
    }
    Ok(BlobPathV1 {
      workspace_id: self.workspace_id,
      parent_dir: format!("{PRIVATE_PREFIX}{}", self.object_id),
      file_id: self.asset_id.clone(),
    })
  }
}

async fn authorize(state: &AppState, user: UserUuid, path: &AssetPath, write: bool) -> Result<()> {
  let uid = state.user_cache.get_user_uid(&user).await?;
  state
    .workspace_access_control
    .enforce_action(&uid, &path.workspace_id, Action::Read)
    .await?;
  state
    .collab_access_control
    .enforce_action(
      &path.workspace_id,
      &uid,
      &path.object_id,
      if write { Action::Write } else { Action::Read },
    )
    .await?;
  guest::ensure_guest_collab_access(state, uid, path.workspace_id, path.object_id, write).await?;
  // Membership/ACL alone must not authorize another workspace's object ID or
  // an asset owned by a document that has been deleted.
  let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM af_collab WHERE oid=$1 AND workspace_id=$2 AND deleted_at IS NULL)")
    .bind(path.object_id).bind(path.workspace_id).fetch_one(&state.pg_pool).await.map_err(AppError::from)?;
  if !exists {
    return Err(AppError::RecordNotFound("Source object not found".into()).into());
  }
  Ok(())
}

#[derive(Serialize)]
struct AssetReceipt {
  provider: &'static str,
  scope: Uuid,
  owner: Uuid,
  key: String,
  media_type: String,
  byte_length: usize,
  sha256: String,
}

async fn put_private_asset(
  user: UserUuid,
  state: web::Data<AppState>,
  path: web::Path<AssetPath>,
  media_type: web::Header<actix_web::http::header::ContentType>,
  mut payload: web::Payload,
) -> Result<HttpResponse> {
  let path = path.into_inner();
  let key = path.key()?;
  authorize(&state, user, &path, true).await?;
  let mut content = Vec::new();
  while let Some(chunk) = payload.try_next().await? {
    if content.len().saturating_add(chunk.len()) > MAX_ASSET_BYTES {
      return Ok(HttpResponse::PayloadTooLarge().finish());
    }
    content.extend_from_slice(&chunk);
  }
  if content.is_empty() || format!("{:x}", Sha256::digest(&content)) != path.asset_id {
    return Err(AppError::InvalidRequest("Asset content digest mismatch".into()).into());
  }
  let length = content.len();
  let media_type = media_type.into_inner().to_string();
  state
    .bucket_storage
    .put_blob_with_content_type(key, ByteStream::from(content), media_type.clone(), length)
    .await?;
  Ok(HttpResponse::Ok().json(AssetReceipt {
    provider: "appflowy.private-assets/1",
    scope: path.workspace_id,
    owner: path.object_id,
    key: path.asset_id.clone(),
    media_type,
    byte_length: length,
    sha256: path.asset_id,
  }))
}

async fn get_private_asset(
  user: UserUuid,
  state: web::Data<AppState>,
  path: web::Path<AssetPath>,
  req: HttpRequest,
) -> Result<HttpResponse> {
  let path = path.into_inner();
  let key = path.key()?;
  authorize(&state, user, &path, false).await?;
  let mut response = get_blob_by_object_key(state, &key, req).await?;
  use actix_web::http::header::{HeaderName, HeaderValue, CACHE_CONTROL, CONTENT_DISPOSITION};
  response
    .headers_mut()
    .insert(CACHE_CONTROL, HeaderValue::from_static("private, no-store"));
  response
    .headers_mut()
    .insert(CONTENT_DISPOSITION, HeaderValue::from_static("attachment"));
  response.headers_mut().insert(
    HeaderName::from_static("x-content-type-options"),
    HeaderValue::from_static("nosniff"),
  );
  Ok(response)
}

#[cfg(test)]
mod tests {
  use super::*;
  use database::file::BlobKey;
  #[test]
  fn reserve_legacy_v0_v1_multipart_and_metadata_keys_without_changing_public_keys() {
    for key in [
      "muse-private-object-owner/hash",
      "workspace/muse-private-object-owner/hash",
      "muse-private-object-owner_hash",
      "safe/muse-private-object-owner/hash",
    ] {
      assert!(deny_public_private_asset(key).is_err());
    }
    for key in [
      "workspace/public/hash",
      "normal-image.jpg",
      "not-muse-private-object-x",
    ] {
      assert!(deny_public_private_asset(key).is_ok());
    }
  }
  #[test]
  fn immutable_key_rejects_path_injection_and_non_digest_ids() {
    let mut path = AssetPath {
      workspace_id: Uuid::new_v4(),
      object_id: Uuid::new_v4(),
      asset_id: "a".repeat(64),
    };
    assert!(path.key().unwrap().object_key().contains(PRIVATE_PREFIX));
    for key in ["../image", "a/b", "ABCD", ""] {
      path.asset_id = key.into();
      assert!(path.key().is_err());
    }
  }
}
