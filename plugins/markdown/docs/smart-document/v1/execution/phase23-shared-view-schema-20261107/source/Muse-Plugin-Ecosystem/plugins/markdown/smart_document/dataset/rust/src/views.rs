//! Linked views share the original database's inline membership. View row
//! orders express presentation, not a second independently copied row store.
use crate::Result;
use collab_database::{
    database::{Database, get_inline_view_id},
    entity::DatabaseView,
    fields::Field,
    views::RowOrder,
};
use std::collections::{HashMap, HashSet};

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

/// Original FieldMap owns the schema; a copied view order cannot hide a field
/// created on an independent branch. Retain the view's order, then the original
/// primary order, with a stable ID tie break for remaining known fields. This
/// only derives a projection, without rewriting per-view order or settings.
pub fn fields(database: &Database, view: &DatabaseView) -> Result<Vec<Field>> {
    let primary = primary(database)?;
    let mut remaining: HashMap<_, _> = database
        .get_fields(None)
        .into_iter()
        .map(|f| (f.id.clone(), f))
        .collect();
    let mut fields = Vec::new();
    for order in view.field_orders.iter().chain(primary.field_orders.iter()) {
        if let Some(field) = remaining.remove(&order.id) {
            fields.push(field);
        }
    }
    let mut missing: Vec<_> = remaining.into_values().collect();
    missing.sort_by(|a, b| a.id.cmp(&b.id));
    fields.extend(missing);
    Ok(fields)
}
