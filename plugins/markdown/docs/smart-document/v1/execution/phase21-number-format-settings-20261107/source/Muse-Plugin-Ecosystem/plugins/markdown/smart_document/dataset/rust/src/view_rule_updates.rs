//! Stable-node edits through the same original Array/Map primitives used by
//! AppFlowy's insert_filter, update_filter and move_sort. No new CRDT/profile.
use collab::{
    preclude::{Any, Array, ArrayPrelim, ArrayRef, Map, MapRef, Out, ReadTxn, TransactionMut},
    util::ArrayExt,
};
use std::collections::HashMap;
type Rule = HashMap<String, Any>;
fn id(rule: &Rule) -> &str {
    match &rule["id"] {
        Any::String(id) => id,
        _ => unreachable!("strict rule decoder checks identity"),
    }
}

fn children(rule: &Rule) -> Option<Vec<Rule>> {
    match rule.get("children") {
        Some(Any::Array(values)) => Some(
            values
                .iter()
                .map(|v| match v {
                    Any::Map(map) => map.as_ref().clone(),
                    _ => unreachable!("strict filter tree decoder"),
                })
                .collect(),
        ),
        _ => None,
    }
}
/// Validation is separate from mutation: legacy atomic children cannot be
/// silently replaced in a shared session. Parent-mode-only edits need no upgrade.
pub fn validate(
    array: &ArrayRef,
    txn: &impl ReadTxn,
    before: &[Rule],
    after: &[Rule],
) -> crate::Result<()> {
    for next in after {
        let Some(old) = before.iter().find(|old| id(old) == id(next)) else {
            continue;
        };
        if old.get("children") == next.get("children") {
            continue;
        }
        let (Some(old_children), Some(next_children)) = (children(old), children(next)) else {
            continue;
        };
        let index = array.index_by_id(txn, id(old)).ok_or("RULE_NODE_MISSING")?;
        let map: MapRef = array
            .get(txn, index)
            .ok_or("RULE_NODE_MISSING")?
            .cast()
            .map_err(|_| "RULE_NODE_MISSING")?;
        let Some(Out::YArray(child_array)) = map.get(txn, "children") else {
            return Err("RULE_NESTING_UPGRADE_REQUIRED".into());
        };
        if child_array.iter(txn).any(|v| !matches!(v, Out::YMap(_))) {
            return Err("RULE_NESTING_UPGRADE_REQUIRED".into());
        }
        validate(&child_array, txn, &old_children, &next_children)?;
    }
    Ok(())
}

pub fn apply(array: &ArrayRef, txn: &mut TransactionMut, before: &[Rule], after: Vec<Rule>) {
    // Removing a rule never removes the independent records it filters.
    for rule in before {
        if !after.iter().any(|next| id(next) == id(rule)) {
            if let Some(index) = array.index_by_id(txn, id(rule)) {
                array.remove(txn, index);
            }
        }
    }
    for rule in &after {
        if before.iter().any(|old| id(old) == id(rule) && old == rule) {
            continue;
        }
        let map: MapRef = array.upsert(txn, id(rule));
        let old_keys = map.keys(txn).map(str::to_string).collect::<Vec<_>>();
        for key in old_keys {
            if !rule.contains_key(&key) {
                map.remove(txn, &key);
            }
        }
        let old = before.iter().find(|old| id(old) == id(rule));
        let nested = children(rule);
        // Leaf semantic fields are still one command. Group metadata is
        // changed only by its own intent, so a child edit cannot restore an old
        // AND/OR mode over a peer's causally independent group edit.
        for (key, value) in rule {
            if key == "children" {
                continue;
            }
            if nested.is_some() && old.is_some_and(|old| old.get(key) == Some(value)) {
                continue;
            }
            map.insert(txn, key.as_str(), value.clone());
        }
        if let Some(next_children) = nested {
            if old.is_some_and(|old| old.get("children") == rule.get("children")) {
                continue;
            }
            let prior = old.and_then(children).unwrap_or_default();
            let child_array = match map.get(txn, "children") {
                Some(Out::YArray(array)) => array,
                _ => map.insert(txn, "children", ArrayPrelim::default()),
            };
            apply(&child_array, txn, &prior, next_children);
        }
    }
    // Yrs move_to retains the existing shared map identity. Clearing and
    // recreating the array here would duplicate peers' concurrent nodes.
    for (position, rule) in after.iter().enumerate() {
        if let Some(from) = array.index_by_id(txn, id(rule)) {
            let to = position as u32;
            if from != to {
                array.move_to(txn, from, to);
            }
        }
    }
}
