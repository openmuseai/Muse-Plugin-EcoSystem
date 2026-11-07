//! Strict commands around the original DateTypeOption/DateCellData codecs.
//! Timezone interpretation belongs here, not in device-local Flutter DateTime.
use crate::Result;
use chrono::{
    DateTime, Datelike, LocalResult, NaiveDate, NaiveDateTime, Offset, TimeZone, Timelike,
};
use chrono_tz::Tz;
use collab::preclude::Any;
use collab_database::{
    fields::{
        Field,
        date_type_option::{DateCellData, DateTypeOption},
    },
    rows::Cell,
};
use serde::Deserialize;
use serde_json::{Value, json};

pub fn options(field: &Field) -> Option<DateTypeOption> {
    if field.field_type != 2 {
        return None;
    }
    let raw = field.get_any_type_option(2)?;
    // Upstream persists enum discriminants as integers, whereas its serde
    // representation uses enum names. Validate the stored representation, then
    // use the original conversion without its silent unknown-value defaults.
    if raw
        .keys()
        .any(|k| !["date_format", "time_format", "timezone_id"].contains(&k.as_str()))
    {
        return None;
    }
    let integer = |key: &str| match raw.get(key)? {
        Any::BigInt(v) => Some(*v),
        Any::Number(v) if v.is_finite() && *v == v.floor() && (0.0..=5.0).contains(v) => {
            Some(*v as i64)
        }
        _ => None,
    };
    if !(0..=5).contains(&integer("date_format")?) || !(0..=1).contains(&integer("time_format")?) {
        return None;
    }
    if !matches!(raw.get("timezone_id"), Some(Any::String(_))) {
        return None;
    }
    let parsed = DateTypeOption::from(raw);
    timezone(&parsed.timezone_id).ok()?;
    Some(parsed)
}
fn timezone(value: &str) -> Result<Tz> {
    if value.len() > 128 {
        return Err("INVALID_TIMEZONE".into());
    }
    value.parse().map_err(|_| "INVALID_TIMEZONE".into())
}
pub fn configure(field: Field, zone: Option<&str>) -> Result<Field> {
    if field.field_type != 2 {
        return if zone.is_some() {
            Err("TYPE_OPTIONS_NOT_ALLOWED".into())
        } else {
            Ok(field)
        };
    }
    let zone = zone.unwrap_or("Etc/UTC");
    timezone(zone)?;
    let mut options = DateTypeOption::default_utc();
    options.timezone_id = zone.into();
    Ok(field.with_type_option_data(2, options.into()))
}
pub fn field_projection(field: &Field) -> Value {
    options(field)
        .map(|v| json!({"timezone":v.timezone_id}))
        .unwrap_or(Value::Null)
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Draft {
    start: Option<String>,
    end: Option<String>,
    include_time: bool,
    is_range: bool,
}
pub(crate) fn valid_instant(ts: i64, tz: Tz) -> Option<DateTime<Tz>> {
    let utc = DateTime::from_timestamp(ts, 0)?;
    // Reject outside our civil range before asking chrono for a local date:
    // applying an offset at chrono's extreme representable year may overflow.
    if !(0..=10000).contains(&utc.year()) {
        return None;
    }
    let value = utc.with_timezone(&tz);
    (1..=9999).contains(&value.year()).then_some(value)
}
/// Existing all-day cells may carry a non-midnight time. Keep that original
/// instant on an unchanged civil date instead of silently erasing hidden data.
fn endpoint(text: &str, timed: bool, tz: Tz, prior: Option<i64>) -> Result<i64> {
    if text.len() > 64 {
        return Err("INVALID_DATE".into());
    }
    if !timed {
        let date = NaiveDate::parse_from_str(text, "%Y-%m-%d").map_err(|_| "INVALID_DATE")?;
        if date.format("%Y-%m-%d").to_string() != text || !(1..=9999).contains(&date.year()) {
            return Err("INVALID_DATE".into());
        }
        if let Some(old) = prior.and_then(|v| valid_instant(v, tz)) {
            if old.date_naive() == date {
                return Ok(old.timestamp());
            }
        }
        return resolve(tz.from_local_datetime(&date.and_hms_opt(0, 0, 0).unwrap()));
    }
    // An explicit offset disambiguates a DST fold, but must agree with the
    // field's timezone at that instant. Fractional seconds must never truncate.
    if let Ok(dt) = DateTime::parse_from_rfc3339(text) {
        if dt.nanosecond() != 0 || !(1..=9999).contains(&dt.year()) || dt.second() > 59 {
            return Err("DATE_PRECISION_UNSUPPORTED".into());
        }
        let local = valid_instant(dt.timestamp(), tz).ok_or("INVALID_DATE")?;
        if local.offset().fix() != *dt.offset() {
            return Err("DATE_OFFSET_MISMATCH".into());
        }
        return Ok(dt.timestamp());
    }
    let parsed = ["%Y-%m-%dT%H:%M:%S", "%Y-%m-%dT%H:%M"]
        .iter()
        .find_map(|format| NaiveDateTime::parse_from_str(text, format).ok())
        .ok_or("INVALID_DATE")?;
    let canonical = if text.len() == 16 {
        "%Y-%m-%dT%H:%M"
    } else {
        "%Y-%m-%dT%H:%M:%S"
    };
    if parsed.format(canonical).to_string() != text
        || !(1..=9999).contains(&parsed.year())
        || parsed.nanosecond() != 0
        || parsed.second() > 59
    {
        return Err("INVALID_DATE".into());
    }
    resolve(tz.from_local_datetime(&parsed))
}
fn resolve(value: LocalResult<DateTime<Tz>>) -> Result<i64> {
    match value {
        LocalResult::Single(v) => Ok(v.timestamp()),
        LocalResult::None => Err("DATE_LOCAL_TIME_GAP".into()),
        LocalResult::Ambiguous(_, _) => Err("DATE_LOCAL_TIME_AMBIGUOUS".into()),
    }
}
pub fn writer_value(field: &Field, value: Value, previous: Option<&Cell>) -> Result<Value> {
    let option = options(field).ok_or("UNSUPPORTED_FIELD")?;
    let old = previous.map(DateCellData::from).unwrap_or_default();
    let tz = timezone(&option.timezone_id)?;
    if value.is_null() {
        // Reminders belong to their own feature. Never erase one via this UI.
        if !old.reminder_id.is_empty() {
            return Err("DATE_REMINDER_UNSUPPORTED".into());
        }
        return Ok(json!(DateCellData::default()));
    }
    let draft: Draft = serde_json::from_value(value).map_err(|_| "INVALID_DATE")?;
    if draft.start.is_none() || (!draft.is_range && draft.end.is_some()) {
        return Err("INVALID_DATE".into());
    }
    let timestamp = endpoint(
        draft.start.as_deref().unwrap(),
        draft.include_time,
        tz,
        (!old.include_time && !draft.include_time)
            .then_some(old.timestamp)
            .flatten(),
    )?;
    let end_timestamp = draft
        .end
        .as_deref()
        .map(|s| {
            endpoint(
                s,
                draft.include_time,
                tz,
                (!old.include_time && !draft.include_time)
                    .then_some(old.end_timestamp)
                    .flatten(),
            )
        })
        .transpose()?;
    if draft.include_time
        && [Some(timestamp), end_timestamp]
            .into_iter()
            .flatten()
            .any(|ts| {
                valid_instant(ts, tz).is_none_or(|v| v.offset().fix().local_minus_utc() % 60 != 0)
            })
    {
        return Err("DATE_OFFSET_PRECISION_UNSUPPORTED".into());
    }
    if end_timestamp.is_some_and(|end| end < timestamp) {
        return Err("DATE_RANGE_REVERSED".into());
    }
    Ok(json!(DateCellData {
        timestamp: Some(timestamp),
        end_timestamp,
        include_time: draft.include_time,
        is_range: draft.is_range,
        reminder_id: old.reminder_id
    }))
}
pub fn unresolved(field: &Field, cell: Option<&Cell>) -> bool {
    if field.field_type != 2 {
        return false;
    }
    let Some(option) = options(field) else {
        return true;
    };
    let Some(cell) = cell else {
        return false;
    };
    let tz = timezone(&option.timezone_id).unwrap();
    for key in ["data", "end_timestamp"] {
        match cell.get(key) {
            None => {}
            Some(Any::String(v)) if v.is_empty() => {}
            Some(Any::String(v))
                if v.parse::<i64>()
                    .ok()
                    .and_then(|ts| valid_instant(ts, tz))
                    .is_some() => {}
            _ => return true,
        }
    }
    for key in ["include_time", "is_range"] {
        if cell.get(key).is_some_and(|v| !matches!(v, Any::Bool(_))) {
            return true;
        }
    }
    if cell
        .get("reminder_id")
        .is_some_and(|v| !matches!(v, Any::String(_)))
    {
        return true;
    }
    let data = DateCellData::from(cell);
    !data.reminder_id.is_empty()
        || (data.include_time
            && [data.timestamp, data.end_timestamp]
                .into_iter()
                .flatten()
                .any(|ts| {
                    valid_instant(ts, tz)
                        .is_none_or(|v| v.offset().fix().local_minus_utc() % 60 != 0)
                }))
        || (data.timestamp.is_none() && data.end_timestamp.is_some())
        || (!data.is_range && data.end_timestamp.is_some())
        || data
            .timestamp
            .zip(data.end_timestamp)
            .is_some_and(|(a, b)| b < a)
}
pub fn projection(field: &Field, cell: Option<&Cell>) -> Value {
    let Some(cell) = cell else {
        return Value::Null;
    };
    if unresolved(field, Some(cell)) {
        return Value::Null;
    }
    let option = options(field).unwrap();
    let tz = timezone(&option.timezone_id).unwrap();
    let value = DateCellData::from(cell);
    let format = |ts: i64| {
        let dt = valid_instant(ts, tz).unwrap();
        if value.include_time {
            dt.to_rfc3339()
        } else {
            dt.format("%Y-%m-%d").to_string()
        }
    };
    json!({"start":value.timestamp.map(format),"end":value.end_timestamp.map(format),
        "includeTime":value.include_time,"isRange":value.is_range,"timezone":option.timezone_id})
}
