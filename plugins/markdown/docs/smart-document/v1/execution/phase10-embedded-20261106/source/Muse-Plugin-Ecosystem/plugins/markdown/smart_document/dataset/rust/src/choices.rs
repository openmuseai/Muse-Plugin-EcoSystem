//! Select semantics reuse original type options and cell ID codecs. This module
//! validates the boundary; it does not replace upstream storage or merging.
use crate::{Result, model};
use collab::preclude::Any;
use collab_database::{
    entity::FieldType,
    fields::{
        Field,
        select_type_option::{SelectOption, SelectOptionColor, SelectOptionIds, SelectTypeOption},
    },
    rows::Cell,
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::collections::HashSet;

#[derive(Clone, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Choice {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub color: u8,
}
pub fn is_choice(field: &Field) -> bool {
    matches!(field.field_type, 3 | 4)
}
fn validate(options: &SelectTypeOption) -> Result<()> {
    if options.options.len() > 64 {
        return Err("TOO_MANY_OPTIONS".into());
    }
    let mut ids = HashSet::new();
    let mut names = HashSet::new();
    for option in &options.options {
        model::address(&option.id)?;
        model::name(&option.name)?;
        if option.id.contains(',') || !ids.insert(&option.id) || !names.insert(&option.name) {
            return Err("INVALID_SELECTION_OPTIONS".into());
        }
    }
    Ok(())
}
pub fn options(field: &Field) -> Option<SelectTypeOption> {
    if !is_choice(field) {
        return None;
    }
    let raw = field
        .get_any_type_option(field.field_type)
        .unwrap_or_default();
    // Upstream's From conversion silently defaults malformed JSON. Validate
    // first; external metadata must remain opaque/read-only instead of erased.
    let parsed = match raw.get("content") {
        None => SelectTypeOption::default(),
        Some(Any::String(s)) => serde_json::from_str::<SelectTypeOption>(s).ok()?,
        _ => return None,
    };
    validate(&parsed).ok()?;
    Some(parsed)
}
pub fn configure(field: Field, choices: &[Choice]) -> Result<Field> {
    if !is_choice(&field) {
        if !choices.is_empty() {
            return Err("TYPE_OPTIONS_NOT_ALLOWED".into());
        }
        return Ok(field);
    }
    let options = SelectTypeOption {
        options: choices
            .iter()
            .map(|v| {
                Ok(SelectOption {
                    id: v.id.clone(),
                    name: v.name.clone(),
                    color: SelectOptionColor::try_from(v.color)
                        .map_err(|_| "INVALID_OPTION_COLOR")?,
                })
            })
            .collect::<Result<Vec<_>>>()?,
        ..Default::default()
    };
    validate(&options)?;
    let ty = field.field_type;
    Ok(field.with_type_option_data(ty, options.into()))
}
pub fn projection(field: &Field) -> Value {
    match options(field) {
        Some(options) => json!(
            options
                .options
                .iter()
                .map(|v| json!({
                    "id":v.id,"name":v.name,"color":u8::from(v.color.clone())
                }))
                .collect::<Vec<_>>()
        ),
        None => Value::Null,
    }
}
pub fn selected(field: &Field, cell: Option<&Cell>) -> Option<Vec<String>> {
    if !is_choice(field) {
        return None;
    }
    Some(
        cell.map(|c| SelectOptionIds::from(c).into_inner())
            .unwrap_or_default(),
    )
}
pub fn unresolved(field: &Field, cell: Option<&Cell>) -> bool {
    let Some(ids) = selected(field, cell) else {
        return false;
    };
    let Some(options) = options(field) else {
        return !ids.is_empty();
    };
    ids.len() > 64
        || (field.field_type == 3 && ids.len() > 1)
        || ids.iter().collect::<HashSet<_>>().len() != ids.len()
        || ids
            .iter()
            .any(|id| !options.options.iter().any(|option| &option.id == id))
}
/// Always send ID objects to the original writer. Its string array branch treats
/// strings as names (and the scalar branch splits commas), so using IDs there
/// would silently clear values or corrupt names containing commas.
pub fn writer_value(field: &Field, value: &Value) -> Result<Value> {
    let options = options(field).ok_or("UNSUPPORTED_FIELD")?;
    let ids = value.as_array().ok_or("INVALID_SELECTION")?;
    if ids.len() > 64 || (field.field_type == i64::from(FieldType::SingleSelect) && ids.len() > 1) {
        return Err("INVALID_SELECTION".into());
    }
    let mut seen = HashSet::new();
    let mut result = Vec::new();
    for id in ids {
        let id = id.as_str().ok_or("INVALID_SELECTION")?;
        if !seen.insert(id) || !options.options.iter().any(|v| v.id == id) {
            return Err("INVALID_SELECTION".into());
        }
        result.push(json!({"id":id}));
    }
    Ok(Value::Array(result))
}
