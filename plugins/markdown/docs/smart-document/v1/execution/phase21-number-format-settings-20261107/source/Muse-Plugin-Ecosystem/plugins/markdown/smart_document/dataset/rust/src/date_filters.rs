//! Field-zone date filter boundary. Original AppFlowy wire enums and evaluator
//! remain authoritative; civil input and SiYuan endpoint selection live here.
use crate::{Result, dates};
use chrono::{Datelike, NaiveDate, TimeZone};
use chrono_tz::Tz;
use collab_database::{
    fields::{Field, date_type_option::DateCellData},
    rows::Cell,
};
use muse_appflowy_view_rules::entities::{DateFilterConditionPB, DateFilterContent, DateFilterPB};
use serde_json::{Value, json};

fn zone(field: &Field) -> Result<Tz> {
    dates::options(field)
        .ok_or("UNSUPPORTED_RULE_FIELD")?
        .timezone_id
        .parse()
        .map_err(|_| "INVALID_TIMEZONE".into())
}
fn instant(value: i64, tz: Tz) -> Result<i64> {
    dates::valid_instant(value, tz)
        .map(|_| value)
        .ok_or("INVALID_DATE_FILTER".into())
}
fn civil(text: &str, tz: Tz) -> Result<i64> {
    if text.len() != 10 {
        return Err("INVALID_DATE_FILTER".into());
    }
    let date = NaiveDate::parse_from_str(text, "%Y-%m-%d").map_err(|_| "INVALID_DATE_FILTER")?;
    if !(1..=9999).contains(&date.year()) || date.format("%Y-%m-%d").to_string() != text {
        return Err("INVALID_DATE_FILTER".into());
    }
    // A filter selects a calendar day, not a wall-clock appointment. Noon avoids
    // midnight DST gaps; reject a wholly skipped civil day instead of shifting it.
    for hour in std::iter::once(12).chain(0..24) {
        if let Some(dt) = tz
            .from_local_datetime(&date.and_hms_opt(hour, 0, 0).unwrap())
            .earliest()
        {
            return Ok(dt.timestamp());
        }
    }
    Err("DATE_LOCAL_TIME_GAP".into())
}
pub fn parse(field: &Field, condition: i64, content: &str) -> Result<(DateFilterPB, Tz)> {
    let condition = DateFilterConditionPB::try_from(
        u8::try_from(condition).map_err(|_| "INVALID_DATE_FILTER")?,
    )
    .map_err(str::to_string)?;
    let tz = zone(field)?;
    let raw: Value = serde_json::from_str(content).map_err(|_| "INVALID_DATE_FILTER")?;
    if raw.as_object().is_none_or(|v| {
        v.keys()
            .any(|k| !["start", "end", "timestamp"].contains(&k.as_str()))
    }) {
        return Err("INVALID_DATE_FILTER".into());
    }
    let data: DateFilterContent = serde_json::from_value(raw).map_err(|_| "INVALID_DATE_FILTER")?;
    for v in [data.start, data.end, data.timestamp].into_iter().flatten() {
        instant(v, tz)?;
    }
    let (mut start, mut end) = (data.start, data.end);
    // SiYuan normalizes reversed between endpoints. Keep imported storage intact.
    if start.zip(end).is_some_and(|(a, b)| a > b) {
        std::mem::swap(&mut start, &mut end);
    }
    Ok((
        DateFilterPB {
            condition,
            start,
            end,
            timestamp: data.timestamp,
        },
        tz,
    ))
}
pub fn visible(
    field: &Field,
    filter: &DateFilterPB,
    tz: Tz,
    cell: Option<&Cell>,
) -> Result<Option<bool>> {
    if dates::unresolved(field, cell) {
        return Err("UNRESOLVED_RULE_CELL".into());
    }
    let original = cell.map(DateCellData::from).unwrap_or_default();
    // SiYuan GetByEndpoint: a non-range uses start; an open range has an empty
    // end. The original evaluator's fallback must not invent that missing end.
    let selected = if filter.condition.is_filter_on_start_timestamp() || !original.is_range {
        original.timestamp
    } else {
        original.end_timestamp
    };
    let selected = DateCellData {
        timestamp: selected,
        end_timestamp: selected,
        ..Default::default()
    };
    Ok(filter.is_visible(&selected, tz))
}
/// Normalize only explicit civil drafts. Bounded traversal precedes recursion;
/// strict Rules::parse subsequently validates IDs, fields, types and conditions.
pub fn normalize(filters: &Value, fields: &[Field]) -> Result<Value> {
    fn walk(node: &mut Value, fields: &[Field], depth: usize, count: &mut usize) -> Result<()> {
        *count += 1;
        if depth > 8 || *count > 64 {
            return Err("VIEW_RULE_QUOTA".into());
        }
        if let Some(children) = node.get_mut("children").and_then(Value::as_array_mut) {
            for child in children {
                walk(child, fields, depth + 1, count)?;
            }
        }
        if node["ty"] == 2 && node["content"].is_object() {
            let f = fields
                .iter()
                .find(|f| Some(f.id.as_str()) == node["field_id"].as_str())
                .ok_or("FIELD_MISSING")?;
            let tz = zone(f)?;
            let data = node["content"].as_object().unwrap();
            if data
                .keys()
                .any(|k| !["start", "end", "timestamp"].contains(&k.as_str()))
            {
                return Err("INVALID_DATE_FILTER".into());
            }
            let mut output = serde_json::Map::new();
            for key in ["start", "end", "timestamp"] {
                let value = match data.get(key) {
                    None | Some(Value::Null) => Value::Null,
                    Some(Value::String(s)) if s.is_empty() => Value::Null,
                    Some(Value::String(s)) => json!(civil(s, tz)?),
                    _ => return Err("INVALID_DATE_FILTER".into()),
                };
                output.insert(key.into(), value);
            }
            node["content"] = Value::String(Value::Object(output).to_string());
        }
        Ok(())
    }
    if filters.to_string().len() > 65536 {
        return Err("VIEW_RULE_QUOTA".into());
    }
    let mut out = filters.clone();
    let mut count = 0;
    for node in out.as_array_mut().ok_or("INVALID_VIEW_RULE")? {
        walk(node, fields, 0, &mut count)?;
    }
    Ok(out)
}
pub fn inputs(filters: &Value, fields: &[Field]) -> Value {
    fn walk(
        node: &Value,
        fields: &[Field],
        out: &mut serde_json::Map<String, Value>,
        depth: usize,
    ) {
        if depth > 8 {
            return;
        }
        if let Some(children) = node["children"].as_array() {
            for child in children {
                walk(child, fields, out, depth + 1);
            }
        }
        if node["ty"] != 2 {
            return;
        }
        let Some(f) = fields
            .iter()
            .find(|f| Some(f.id.as_str()) == node["field_id"].as_str())
        else {
            return;
        };
        let Ok((rule, tz)) = parse(
            f,
            node["condition"].as_i64().unwrap_or(-1),
            node["content"].as_str().unwrap_or(""),
        ) else {
            return;
        };
        let render = |v: Option<i64>| {
            v.and_then(|v| dates::valid_instant(v, tz))
                .map(|v| v.format("%Y-%m-%d").to_string())
        };
        if let Some(id) = node["id"].as_str() {
            out.insert(id.into(),json!({"start":render(rule.start),"end":render(rule.end),"timestamp":render(rule.timestamp)}));
        }
    }
    let mut out = serde_json::Map::new();
    if let Some(nodes) = filters.as_array() {
        for n in nodes.iter().take(32) {
            walk(n, fields, &mut out, 0);
        }
    }
    Value::Object(out)
}
