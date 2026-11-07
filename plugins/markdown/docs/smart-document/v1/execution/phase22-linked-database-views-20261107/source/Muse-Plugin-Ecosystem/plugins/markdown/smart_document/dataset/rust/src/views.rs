//! Linked views share the original database's inline membership. View row
//! orders express presentation, not a second independently copied row store.
use crate::Result;
use collab_database::{
    database::{Database, get_inline_view_id},
    entity::DatabaseView,
    views::RowOrder,
};
use std::collections::HashSet;

pub fn primary(database: &Database) -> Result<DatabaseView> {
    let id = get_inline_view_id(&database.collab).ok_or("INLINE_VIEW_REQUIRED")?;
    database
        .get_view(&id)
        .ok_or_else(|| "INLINE_VIEW_REQUIRED".into())
}

/// A new linked view may not know a concurrently inserted row. Preserve its
/// original manual order, append missing primary members in converged primary
/// order, and exclude stale members deleted from the primary. Pure projection:
/// no read-time CRDT writes, migration, replicated repair or row resurrection.
pub fn rows(database: &Database, view: &DatabaseView) -> Result<Vec<RowOrder>> {
    let primary = primary(database)?;
    let members: HashSet<_> = primary.row_orders.iter().map(|r| &r.id).collect();
    let mut seen = HashSet::new();
    let mut rows = Vec::new();
    for row in view.row_orders.iter().chain(primary.row_orders.iter()) {
        if members.contains(&row.id) && seen.insert(row.id.clone()) {
            rows.push(row.clone());
        }
    }
    Ok(rows)
}
