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
  ty: CollabType,
) -> AppResult<()> {
  if rows.is_empty() {
    return Ok(());
  }
  let partition = partition_key_from_collab_type(&ty);
  let matched = rows
    .iter()
    .filter(|(scope, kind, _)| scope == workspace && *kind == partition)
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
    assert!(validate_registration(&[], &ws, CollabType::DatabaseRow).is_ok());
    let live = [(ws, 4, false)];
    assert!(validate_registration(&live, &ws, CollabType::DatabaseRow).is_ok());
    assert!(matches!(
      validate_registration(&live, &Uuid::new_v4(), CollabType::DatabaseRow),
      Err(AppError::RecordNotFound(_))
    ));
    assert!(matches!(
      validate_registration(&live, &ws, CollabType::Document),
      Err(AppError::RecordNotFound(_))
    ));
    assert!(matches!(
      validate_registration(&[(ws, 4, true)], &ws, CollabType::DatabaseRow),
      Err(AppError::RecordDeleted(_))
    ));
  }
}
