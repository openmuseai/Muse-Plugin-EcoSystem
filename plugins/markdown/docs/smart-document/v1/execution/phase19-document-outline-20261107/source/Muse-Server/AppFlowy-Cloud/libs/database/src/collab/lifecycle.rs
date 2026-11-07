//! Authoritative lifecycle boundary before memory/Redis state or realtime writes.
use crate::collab::{partition_key_from_collab_type, AppResult};
use app_error::AppError;
use collab_entity::CollabType;
use sqlx::PgPool;
use uuid::Uuid;

/// Keep the original pre-persistence creation path for an unknown ID. Once an
/// ID is registered, another workspace/type or a tombstone must never be served
/// from a stale cache or reconstructed from Redis updates.
pub async fn check_collab_lifecycle(
  pool: &PgPool,
  workspace_id: &Uuid,
  object_id: &Uuid,
  collab_type: CollabType,
) -> AppResult<()> {
  check_registration(pool, workspace_id, object_id, Some(collab_type)).await
}

/// Awareness/permission messages identify an object without choosing its content type.
pub async fn check_collab_lifecycle_any_type(
  pool: &PgPool,
  workspace_id: &Uuid,
  object_id: &Uuid,
) -> AppResult<()> {
  check_registration(pool, workspace_id, object_id, None).await
}
async fn check_registration(
  pool: &PgPool,
  workspace_id: &Uuid,
  object_id: &Uuid,
  collab_type: Option<CollabType>,
) -> AppResult<()> {
  let registrations = sqlx::query_as::<_, (Uuid, i32, bool)>(
    "SELECT workspace_id, partition_key, deleted_at IS NOT NULL FROM af_collab WHERE oid=$1",
  )
  .bind(object_id)
  .fetch_all(pool)
  .await?;
  validate_registration(&registrations, workspace_id, collab_type)
}

fn validate_registration(
  rows: &[(Uuid, i32, bool)],
  workspace: &Uuid,
  ty: Option<CollabType>,
) -> AppResult<()> {
  if rows.is_empty() {
    return Ok(());
  }
  let partition = ty.as_ref().map(partition_key_from_collab_type);
  let matched = rows
    .iter()
    .filter(|(scope, kind, _)| scope == workspace && partition.map(|p| *kind == p).unwrap_or(true))
    .collect::<Vec<_>>();
  if matched.is_empty() {
    return Err(AppError::RecordNotFound(
      "Collab not found in this scope/type".into(),
    ));
  }
  if matched.iter().all(|(_, _, deleted)| *deleted) {
    return Err(AppError::RecordDeleted("Collab has been deleted".into()));
  }
  Ok(())
}

#[cfg(test)]
mod tests {
  use super::*;
  #[test]
  fn registered_object_scope_type_and_tombstone_override_cached_state() {
    let ws = Uuid::new_v4();
    assert!(validate_registration(&[], &ws, Some(CollabType::DatabaseRow)).is_ok());
    let live = [(ws, 4, false)];
    assert!(validate_registration(&live, &ws, None).is_ok());
    assert!(matches!(
      validate_registration(&[(ws, 4, true)], &ws, None),
      Err(AppError::RecordDeleted(_))
    ));
    assert!(validate_registration(&live, &ws, Some(CollabType::DatabaseRow)).is_ok());
    assert!(matches!(
      validate_registration(&live, &Uuid::new_v4(), Some(CollabType::DatabaseRow)),
      Err(AppError::RecordNotFound(_))
    ));
    assert!(matches!(
      validate_registration(&live, &ws, Some(CollabType::Document)),
      Err(AppError::RecordNotFound(_))
    ));
    assert!(matches!(
      validate_registration(&[(ws, 4, true)], &ws, Some(CollabType::DatabaseRow)),
      Err(AppError::RecordDeleted(_))
    ));
  }
}
