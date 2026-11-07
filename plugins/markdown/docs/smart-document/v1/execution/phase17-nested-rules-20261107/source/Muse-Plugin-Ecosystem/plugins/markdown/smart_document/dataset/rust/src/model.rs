use crate::{Result, choices, dates};
use collab::preclude::{Any, encoding::serde::from_any};
use collab_database::{
    entity::FieldType,
    fields::{
        Field, TypeOptionCellReader, TypeOptionCellWriter, type_option_cell_reader,
        type_option_cell_writer,
    },
    fields::{number_type_option::NumberTypeOption, url_type_option::URLTypeOption},
    rows::Cell,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::HashMap;

#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ObjectState {
    pub object_id: String,
    pub collab_type: i32,
    pub doc_state: String,
}
#[derive(Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Bundle {
    pub profile: String,
    pub object_id: String,
    pub objects: Vec<ObjectState>,
}

pub fn semantic(field: &Field) -> &'static str {
    match field.field_type {
        0 => "text",
        1 => "number",
        2 => "date",
        3 => "singleSelect",
        4 => "multiSelect",
        5 => "checkbox",
        6 => "url",
        _ => "unsupported",
    }
}
pub fn field_type(semantic: &str) -> Result<FieldType> {
    match semantic {
        "text" => Ok(FieldType::RichText),
        "number" => Ok(FieldType::Number),
        "date" => Ok(FieldType::DateTime),
        "singleSelect" => Ok(FieldType::SingleSelect),
        "multiSelect" => Ok(FieldType::MultiSelect),
        "checkbox" => Ok(FieldType::Checkbox),
        "url" => Ok(FieldType::URL),
        _ => Err("UNSUPPORTED_FIELD".into()),
    }
}
pub fn address(id: &str) -> Result<()> {
    if id.is_empty() || id.len() > 128 || id.chars().any(char::is_control) {
        Err("INVALID_ID".into())
    } else {
        Ok(())
    }
}
pub fn name(value: &str) -> Result<()> {
    if value.trim().is_empty() || value.len() > 512 || value.chars().any(char::is_control) {
        Err("INVALID_NAME".into())
    } else {
        Ok(())
    }
}
/// Invalid/unknown options remain encoded and read-only. Never call upstream
/// infallible conversions (which unwrap) on unvalidated external metadata.
pub fn readers(
    field: &Field,
) -> Option<(Box<dyn TypeOptionCellReader>, Box<dyn TypeOptionCellWriter>)> {
    let ty = field_type(semantic(field)).ok()?;
    let options = field.get_any_type_option(ty).unwrap_or_default();
    if field.field_type == 1 {
        let parsed: NumberTypeOption = from_any(&Any::from(options.clone())).ok()?;
        let raw_format = match options.get("format") {
            None => 0,
            Some(Any::BigInt(v)) => *v,
            Some(Any::Number(v))
                if v.is_finite() && *v == v.floor() && (0.0..=1000.0).contains(v) =>
            {
                *v as i64
            }
            _ => return None,
        };
        if parsed.format.value() != raw_format || parsed.scale > 28 {
            return None;
        }
    }
    if field.field_type == 6 {
        let _: URLTypeOption = from_any(&Any::from(options.clone())).ok()?;
    }
    if choices::is_choice(field) && choices::options(field).is_none() {
        return None;
    }
    if field.field_type == 2 && dates::options(field).is_none() {
        return None;
    }
    Some((
        type_option_cell_reader(options.clone(), &ty),
        type_option_cell_writer(options, &ty),
    ))
}
pub fn logical_cell(cell: Option<&Cell>) -> Option<&Cell> {
    cell.filter(|c| {
        c.keys().any(|k| {
            k != collab_database::rows::CREATED_AT && k != collab_database::rows::LAST_MODIFIED
        })
    })
}
pub fn hash(cell: Option<&Cell>) -> String {
    let cell = logical_cell(cell);
    format!(
        "{:x}",
        Sha256::digest(serde_json::to_vec(&serde_json::to_value(cell).unwrap()).unwrap())
    )
}
pub fn field_hash(field: &Field) -> String {
    format!(
        "{:x}",
        Sha256::digest(serde_json::to_vec(&serde_json::to_value(field).unwrap()).unwrap())
    )
}
pub fn write(field: &Field, value: Value) -> Result<Cell> {
    write_existing(field, value, None)
}
pub fn write_existing(field: &Field, value: Value, previous: Option<&Cell>) -> Result<Cell> {
    let (_, writer) = readers(field).ok_or("UNSUPPORTED_FIELD")?;
    if field.field_type == 2 {
        if dates::unresolved(field, previous) {
            return Err("UNSUPPORTED_DATE_VALUE".into());
        }
        return Ok(writer.convert_json_to_cell(dates::writer_value(field, value, previous)?));
    }
    if choices::is_choice(field) {
        return Ok(writer.convert_json_to_cell(choices::writer_value(field, &value)?));
    }
    let valid = match semantic(field) {
        "text" | "url" => value.is_string(),
        "checkbox" => value.is_boolean(),
        "number" => value.is_string() || value.is_number(),
        _ => false,
    };
    if !valid || value.to_string().len() > 65536 {
        return Err("INVALID_CELL_VALUE".into());
    }
    Ok(writer.convert_json_to_cell(value))
}
pub fn raw(cell: Option<&Cell>) -> Value {
    serde_json::to_value(cell.cloned().unwrap_or_else(HashMap::new)).unwrap_or(Value::Null)
}
