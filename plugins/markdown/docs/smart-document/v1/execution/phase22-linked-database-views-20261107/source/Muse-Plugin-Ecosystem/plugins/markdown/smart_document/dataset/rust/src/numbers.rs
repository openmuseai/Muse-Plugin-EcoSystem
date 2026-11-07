//! Numeric command/projection boundary. Original NumberCellData and type-option
//! codecs remain authoritative; formatted display is never an editing source.
use crate::Result;
use collab::preclude::{Any, encoding::serde::from_any};
use collab_database::{
    fields::{Field, number_type_option::NumberTypeOption},
    rows::Cell,
    template::{entity::CELL_DATA, number_parse::NumberCellData},
};
use rust_decimal::Decimal;
use serde_json::Value;

pub fn options(field: &Field) -> Option<NumberTypeOption> {
    if field.field_type != 1 {
        return None;
    }
    let options = field.get_any_type_option(1).unwrap_or_default();
    let parsed: NumberTypeOption = from_any(&Any::from(options.clone())).ok()?;
    let raw = match options.get("format") {
        None => 0,
        Some(Any::BigInt(v)) => *v,
        Some(Any::Number(v)) if v.is_finite() && *v == v.floor() && (0.0..=1000.0).contains(v) => {
            *v as i64
        }
        _ => return None,
    };
    (parsed.format.value() == raw && parsed.scale <= 28).then_some(parsed)
}

/// Validate the whole literal before calling upstream's intentionally lenient
/// formatter. Exact decimal parsing rejects truncation, overflow and underflow.
pub fn canonical(literal: &str) -> Result<String> {
    let text = literal.trim();
    if text.is_empty() {
        return Ok(String::new());
    }
    if text.len() > 128 {
        return Err("INVALID_NUMBER_VALUE".into());
    }
    let bytes = text.as_bytes();
    let mut i = 0;
    if matches!(bytes.first(), Some(b'+') | Some(b'-')) {
        i += 1;
    }
    let mut digits = 0;
    while i < bytes.len() && bytes[i].is_ascii_digit() {
        i += 1;
        digits += 1;
    }
    if bytes.get(i) == Some(&b'.') {
        i += 1;
        while i < bytes.len() && bytes[i].is_ascii_digit() {
            i += 1;
            digits += 1;
        }
    }
    if digits == 0 {
        return Err("INVALID_NUMBER_VALUE".into());
    }
    let mantissa_end = i;
    if matches!(bytes.get(i), Some(b'e') | Some(b'E')) {
        i += 1;
        if matches!(bytes.get(i), Some(b'+') | Some(b'-')) {
            i += 1;
        }
        let start = i;
        while i < bytes.len() && bytes[i].is_ascii_digit() {
            i += 1;
        }
        if start == i {
            return Err("INVALID_NUMBER_VALUE".into());
        }
    }
    if i != bytes.len() {
        return Err("INVALID_NUMBER_VALUE".into());
    }
    let base =
        Decimal::from_str_exact(&text[..mantissa_end]).map_err(|_| "INVALID_NUMBER_VALUE")?;
    let value = if mantissa_end == text.len() {
        base
    } else {
        Decimal::from_scientific(text).map_err(|_| "INVALID_NUMBER_VALUE")?
    };
    Ok(value.to_string())
}

pub fn input(field: &Field, cell: Option<&Cell>) -> Option<String> {
    options(field)?;
    match cell {
        None => Some(String::new()),
        Some(cell) => match cell.get(CELL_DATA) {
            Some(Any::String(_)) => {
                let raw = NumberCellData::from(cell).0;
                canonical(&raw).ok()?;
                Some(raw)
            }
            _ => None,
        },
    }
}
pub fn unresolved(field: &Field, cell: Option<&Cell>) -> bool {
    field.field_type == 1 && input(field, cell).is_none()
}
pub fn writer_value(value: Value) -> Result<Value> {
    let raw = match value {
        Value::String(s) => s,
        Value::Number(n) => n.to_string(),
        _ => return Err("INVALID_NUMBER_VALUE".into()),
    };
    Ok(Value::String(canonical(&raw)?))
}
