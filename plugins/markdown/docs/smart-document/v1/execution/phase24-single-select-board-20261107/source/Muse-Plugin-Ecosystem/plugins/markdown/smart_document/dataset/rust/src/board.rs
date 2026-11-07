//! Board is a projection of original GroupSetting + SelectOptionIds + Row objects.
//! Ordering follows AppFlowy group/configuration.rs::merge_groups (17e24f8),
//! including field-ID no-status and retained visibility. No parallel card store.
use crate::{Result, choices, model};
use collab_database::{
    entity::DatabaseView,
    fields::Field,
    views::{DatabaseLayout, GroupSetting},
};
use serde::Deserialize;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::collections::HashSet;

#[derive(Default, Deserialize)]
#[serde(deny_unknown_fields)]
struct Configuration {
    #[serde(default)]
    hide_empty: bool,
}
pub struct Board<'a> {
    pub field: &'a Field,
    pub hash: String,
    hide_empty: bool,
    groups: Vec<Value>,
}
impl<'a> Board<'a> {
    pub fn parse(view: &DatabaseView, fields: &'a [Field]) -> Result<Self> {
        if view.layout != DatabaseLayout::Board {
            return Err("NOT_BOARD".into());
        }
        // Multiple competing group configs, unknown settings and unsupported
        // field types remain opaque. Never silently choose another field.
        if view.group_settings.len() != 1 {
            return Err("UNSUPPORTED_BOARD_GROUPS".into());
        }
        let raw = view.group_settings[0].clone();
        if raw
            .keys()
            .any(|k| !["id", "field_id", "ty", "groups", "content"].contains(&k.as_str()))
        {
            return Err("UNSUPPORTED_BOARD_GROUPS".into());
        }
        if let Some(collab::preclude::Any::Array(groups)) = raw.get("groups") {
            for group in groups.iter() {
                if let collab::preclude::Any::Map(group) = group {
                    if group
                        .keys()
                        .any(|k| !["id", "visible"].contains(&k.as_str()))
                    {
                        return Err("UNSUPPORTED_BOARD_GROUPS".into());
                    }
                }
            }
        }
        let setting = GroupSetting::try_from(raw).map_err(|_| "INVALID_BOARD_GROUPS")?;
        let field = fields
            .iter()
            .find(|f| f.id == setting.field_id)
            .ok_or("BOARD_FIELD_MISSING")?;
        if field.field_type != 3 || setting.field_type != 3 {
            return Err("UNSUPPORTED_BOARD_FIELD".into());
        }
        let options = choices::options(field).ok_or("UNSUPPORTED_BOARD_OPTIONS")?;
        if options.options.iter().any(|o| o.id == field.id) {
            return Err("AMBIGUOUS_BOARD_GROUP_ID".into());
        }
        let config: Configuration = if setting.content.is_empty() {
            Configuration::default()
        } else {
            serde_json::from_str(&setting.content).map_err(|_| "UNSUPPORTED_BOARD_CONFIGURATION")?
        };
        let mut groups: Vec<Value> = options.options.iter().map(|o| json!({"id":o.id,"name":o.name,"color":u8::from(o.color.clone()),"visible":true})).collect();
        let no_status = json!({"id":field.id,"name":"未分组","color":0,"visible":true});
        let mut ordered = Vec::new();
        let mut seen = HashSet::new();
        let mut no_status_seen = false;
        for old in &setting.groups {
            if !seen.insert(&old.id) {
                return Err("DUPLICATE_BOARD_GROUP".into());
            }
            let item = if old.id == field.id {
                no_status_seen = true;
                Some(no_status.clone())
            } else {
                groups
                    .iter()
                    .position(|g| g["id"] == old.id)
                    .map(|i| groups.remove(i))
            };
            if let Some(mut item) = item {
                item["visible"] = json!(old.visible);
                ordered.push(item);
            }
        }
        ordered.extend(groups);
        if !no_status_seen {
            ordered.insert(0, no_status);
        }
        let hash = format!(
            "{:x}",
            Sha256::digest(
                serde_json::to_vec(
                    &json!({"groups":view.group_settings,"fieldHash":model::field_hash(field)})
                )
                .unwrap()
            )
        );
        Ok(Self {
            field,
            hash,
            hide_empty: config.hide_empty,
            groups: ordered,
        })
    }
    pub fn selection(&self, group_id: &str) -> Result<Value> {
        if !self
            .groups
            .iter()
            .any(|g| g["id"] == group_id && g["visible"] == true)
        {
            return Err("BOARD_GROUP_MISSING".into());
        }
        Ok(if group_id == self.field.id {
            json!([])
        } else {
            json!([group_id])
        })
    }
    pub fn project(&self, rows: &[Value]) -> Value {
        let mut groups = self.groups.clone();
        for group in &mut groups {
            group["rowIds"] = json!([]);
        }
        let mut unresolved = Vec::new();
        let mut unloaded = Vec::new();
        for row in rows {
            if row["loaded"] != true {
                unloaded.push(row["id"].clone());
                continue;
            }
            let cell = &row["cells"][&self.field.id];
            if cell["unresolvedOptions"] == true {
                unresolved.push(row["id"].clone());
                continue;
            }
            let ids = cell["selectedOptionIds"].as_array();
            let group_id = ids
                .and_then(|v| v.first())
                .and_then(Value::as_str)
                .unwrap_or(&self.field.id);
            if let Some(group) = groups.iter_mut().find(|g| g["id"] == group_id) {
                group["rowIds"]
                    .as_array_mut()
                    .unwrap()
                    .push(row["id"].clone());
            } else {
                unresolved.push(row["id"].clone());
            }
        }
        let targets: Vec<_> = groups
            .iter()
            .filter(|g| g["visible"] == true)
            .cloned()
            .collect();
        groups.retain(|g| {
            g["visible"] == true
                && (!self.hide_empty || !g["rowIds"].as_array().unwrap().is_empty())
        });
        json!({"ready":true,"fieldId":self.field.id,"hash":self.hash,"groups":groups,"targets":targets,"unresolvedRowIds":unresolved,"unloadedRowIds":unloaded})
    }
}
pub fn projection(view: &DatabaseView, fields: &[Field], rows: &[Value]) -> Value {
    if view.layout != DatabaseLayout::Board {
        return Value::Null;
    }
    match Board::parse(view, fields) {
        Ok(board) => board.project(rows),
        Err(error) => json!({"ready":false,"error":error}),
    }
}
