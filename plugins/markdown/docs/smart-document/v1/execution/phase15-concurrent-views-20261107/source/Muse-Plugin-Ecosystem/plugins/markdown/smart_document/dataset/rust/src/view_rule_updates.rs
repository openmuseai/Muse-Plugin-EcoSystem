//! Stable-node edits through the same original Array/Map primitives used by
//! AppFlowy's insert_filter, update_filter and move_sort. No new CRDT/profile.
use collab::{
    preclude::{Any, Array, ArrayRef, Map, MapRef, TransactionMut},
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
        // Force a changed leaf's semantic fields together. In particular, do
        // not use try_update to skip an equal condition while writing content.
        // Original Y.Map conflict resolution remains authoritative; this is
        // not a server compare-and-swap or a new undo algorithm.
        for (key, value) in rule {
            map.insert(txn, key.as_str(), value.clone());
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
