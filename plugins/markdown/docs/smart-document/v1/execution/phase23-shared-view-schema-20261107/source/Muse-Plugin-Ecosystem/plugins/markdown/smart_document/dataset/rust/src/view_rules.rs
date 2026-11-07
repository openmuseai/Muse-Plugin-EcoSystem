//! Strict adapter over original AppFlowy view storage and pure evaluators.
//! This module has no transport, Flutter, resource routing or wall clock.
use crate::{Result, choices, model};
use collab::preclude::{Any, encoding::serde::from_any};
use collab_database::{
    entity::DatabaseView,
    fields::{Field, date_type_option::DateCellData, number_type_option::NumberTypeOption},
    rows::Cell,
};
use muse_appflowy_view_rules::entities::*;
use rust_decimal::Decimal;
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{
    cmp::Ordering,
    collections::{HashMap, HashSet},
    str::FromStr,
};

pub fn rules_hash(view: &DatabaseView) -> String {
    digest(&json!({"filters":view.filters,"sorts":view.sorts}))
}
pub fn fields_hash(fields: &[Field]) -> String {
    digest(&json!(fields))
}
fn digest(value: &Value) -> String {
    format!("{:x}", Sha256::digest(serde_json::to_vec(value).unwrap()))
}
#[derive(Clone)]
enum Filter {
    Group(bool, Vec<Filter>),
    Text(String, TextFilterPB),
    Number(String, NumberFilterPB),
    Check(String, bool),
    Date(String, DateFilterPB, chrono_tz::Tz),
    Select(String, SelectOptionFilterPB),
}
struct Sort {
    field: String,
    descending: bool,
}
pub struct Rules {
    filters: Vec<Filter>,
    sorts: Vec<Sort>,
}
fn string<'a>(value: &'a Value, key: &str) -> Result<&'a str> {
    value
        .get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("INVALID_VIEW_RULE:{key}"))
}
fn integer(value: &Value, key: &str) -> Result<i64> {
    value
        .get(key)
        .and_then(Value::as_i64)
        .ok_or_else(|| format!("INVALID_VIEW_RULE:{key}"))
}
fn keys(value: &Value, allowed: &[&str]) -> Result<()> {
    if value
        .as_object()
        .is_none_or(|m| m.keys().any(|k| !allowed.contains(&k.as_str())))
    {
        return Err("UNSUPPORTED_VIEW_RULE".into());
    }
    Ok(())
}
fn identity(value: &Value, ids: &mut HashSet<String>) -> Result<()> {
    let id = string(value, "id")?;
    model::address(id)?;
    if !ids.insert(id.into()) {
        return Err("DUPLICATE_RULE_ID".into());
    }
    Ok(())
}
impl Rules {
    pub fn prefill(&self, fields: &[Field]) -> Result<HashMap<String, Cell>> {
        use muse_appflowy_view_rules::prefill::PreFillCellsWithFilter;
        fn minimal<'a>(filter: &'a Filter, out: &mut Vec<&'a Filter>) {
            match filter {
                Filter::Group(true, children) => {
                    for child in children {
                        minimal(child, out);
                    }
                }
                Filter::Group(false, children) => {
                    if let Some(first) = children.first() {
                        minimal(first, out);
                    }
                }
                leaf => out.push(leaf),
            }
        }
        let mut required = vec![];
        for filter in &self.filters {
            minimal(filter, &mut required);
        }
        fn field_id<'a>(filter: &&'a Filter) -> Option<&'a str> {
            match filter {
                Filter::Text(id, _)
                | Filter::Number(id, _)
                | Filter::Check(id, _)
                | Filter::Select(id, _)
                | Filter::Date(id, _, _) => Some(id.as_str()),
                _ => None,
            }
        }
        let mut counts = HashMap::new();
        for id in required.iter().filter_map(field_id) {
            *counts.entry(id).or_insert(0) += 1;
        }
        let mut cells = HashMap::new();
        for filter in &required {
            let Some(id) = field_id(filter) else {
                continue;
            };
            if counts[id] != 1 {
                continue;
            }
            let field = fields.iter().find(|f| f.id == id).ok_or("FIELD_MISSING")?;
            let cell = match filter {
                Filter::Text(_, f) => f.get_compliant_cell(field),
                Filter::Number(_, f) => f.get_compliant_cell(field),
                Filter::Select(_, f) => f.get_compliant_cell(field),
                Filter::Date(_, filter, zone) => filter
                    .get_compliant_cell_in_zone(field, *zone)
                    .filter(|cell| {
                        crate::dates::unresolved(field, Some(cell)) == false
                            && crate::date_filters::visible(field, filter, *zone, Some(cell)).ok()
                                == Some(Some(true))
                    }),
                Filter::Check(_, true) => Some(model::write(field, json!(true))?),
                _ => None,
            };
            if let Some(cell) = cell {
                cells.insert(id.into(), cell);
            }
        }
        Ok(cells)
    }

    pub fn parse(filters: &Value, sorts: &Value, fields: &[Field]) -> Result<Self> {
        let filters = filters.as_array().ok_or("INVALID_VIEW_RULE")?;
        let sorts = sorts.as_array().ok_or("INVALID_VIEW_RULE")?;
        if filters.len() > 32
            || sorts.len() > 16
            || filters
                .iter()
                .chain(sorts)
                .map(|v| v.to_string().len())
                .sum::<usize>()
                > 65536
        {
            return Err("VIEW_RULE_QUOTA".into());
        }
        let mut ids = HashSet::new();
        let mut count = 0;
        let filters = filters
            .iter()
            .map(|v| parse_filter(v, fields, 0, &mut count, &mut ids))
            .collect::<Result<_>>()?;
        let mut sort_fields = HashSet::new();
        let sorts = sorts
            .iter()
            .map(|v| {
                keys(v, &["id", "field_id", "condition"])?;
                identity(v, &mut ids)?;
                let field = field(v, fields)?;
                if !sort_fields.insert(field.id.clone()) {
                    return Err("DUPLICATE_SORT_FIELD".into());
                }
                if !matches!(integer(v, "condition")?, 0 | 1) {
                    return Err("UNSUPPORTED_SORT_CONDITION".into());
                }
                Ok(Sort {
                    field: field.id.clone(),
                    descending: integer(v, "condition")? == 1,
                })
            })
            .collect::<Result<_>>()?;
        Ok(Self { filters, sorts })
    }
    pub fn project(&self, rows: &mut Vec<Value>, fields: &[Field]) -> Result<()> {
        // Precompute keys once. Validate every loaded row BEFORE changing the
        // projection: corrupt/unknown cells cannot silently disappear.
        let mut keys: HashMap<String, Vec<Option<Key>>> = HashMap::new();
        let mut visible = HashSet::new();
        let mut referenced = HashSet::new();
        for filter in &self.filters {
            filter.references(&mut referenced);
        }
        referenced.extend(self.sorts.iter().map(|s| s.field.as_str()));
        for row in rows.iter().filter(|r| r["loaded"] == true) {
            let id = row["id"].as_str().ok_or("INVALID_ROW_ID")?;
            for f in fields.iter().filter(|f| referenced.contains(f.id.as_str())) {
                validate_cell(row, f)?;
            }

            let matches = self
                .filters
                .iter()
                .map(|f| f.visible(row, fields))
                .collect::<Result<Vec<_>>>()?
                .into_iter()
                .flatten()
                .all(|v| v);
            if matches {
                visible.insert(id.to_string());
            }
            let values = self
                .sorts
                .iter()
                .map(|s| {
                    sort_key(
                        row,
                        fields
                            .iter()
                            .find(|f| f.id == s.field)
                            .ok_or("FIELD_MISSING")?,
                    )
                })
                .collect::<Result<Vec<_>>>()?;
            keys.insert(id.to_string(), values);
        }
        rows.retain(|r| r["loaded"] != true || visible.contains(r["id"].as_str().unwrap()));
        // Stable manual order is the tie breaker. Empty is always last,
        // including descending, as in original AppFlowy/SiYuan views.
        if self.sorts.is_empty() {
            return Ok(());
        }
        rows.sort_by(|a, b| {
            match (a["loaded"] == true, b["loaded"] == true) {
                (false, false) => return Ordering::Equal,
                (false, true) => return Ordering::Greater,
                (true, false) => return Ordering::Less,
                _ => {}
            }
            let a = &keys[a["id"].as_str().unwrap()];
            let b = &keys[b["id"].as_str().unwrap()];
            for (i, s) in self.sorts.iter().enumerate() {
                let order = match (&a[i], &b[i]) {
                    (None, None) => Ordering::Equal,
                    (None, Some(_)) => Ordering::Greater,
                    (Some(_), None) => Ordering::Less,
                    (Some(a), Some(b)) => {
                        let o = a.cmp(b);
                        if s.descending { o.reverse() } else { o }
                    }
                };
                if !order.is_eq() {
                    return order;
                }
            }
            Ordering::Equal
        });
        Ok(())
    }
}
fn field<'a>(value: &Value, fields: &'a [Field]) -> Result<&'a Field> {
    let id = string(value, "field_id")?;
    let f = fields.iter().find(|f| f.id == id).ok_or("FIELD_MISSING")?;
    if model::readers(f).is_none() {
        return Err("UNSUPPORTED_RULE_FIELD".into());
    }
    Ok(f)
}
fn parse_filter(
    v: &Value,
    fields: &[Field],
    depth: usize,
    count: &mut usize,
    ids: &mut HashSet<String>,
) -> Result<Filter> {
    *count += 1;
    if depth > 8 || *count > 64 {
        return Err("VIEW_RULE_QUOTA".into());
    }
    identity(v, ids)?;
    match v
        .get("filter_type")
        .map(|_| integer(v, "filter_type"))
        .transpose()?
        .unwrap_or(2)
    {
        kind @ (0 | 1) => {
            keys(v, &["id", "filter_type", "children"])?;
            let children = v["children"].as_array().ok_or("INVALID_VIEW_RULE")?;
            Ok(Filter::Group(
                kind == 0,
                children
                    .iter()
                    .map(|c| parse_filter(c, fields, depth + 1, count, ids))
                    .collect::<Result<_>>()?,
            ))
        }
        2 => {
            keys(
                v,
                &[
                    "id",
                    "filter_type",
                    "field_id",
                    "ty",
                    "condition",
                    "content",
                ],
            )?;
            let f = field(v, fields)?;
            if integer(v, "ty")? != f.field_type {
                return Err("RULE_FIELD_TYPE_CHANGED".into());
            }
            let n = integer(v, "condition")?;
            let content = string(v, "content")?.to_string();
            if content.len() > 4096 {
                return Err("VIEW_RULE_QUOTA".into());
            }
            let id = f.id.clone();
            match f.field_type {
                0 | 6 => {
                    use TextFilterConditionPB::*;
                    let condition = match n {
                        0 => TextIs,
                        1 => TextIsNot,
                        2 => TextContains,
                        3 => TextDoesNotContain,
                        4 => TextStartsWith,
                        5 => TextEndsWith,
                        6 => TextIsEmpty,
                        7 => TextIsNotEmpty,
                        _ => return Err("UNSUPPORTED_FILTER_CONDITION".into()),
                    };
                    Ok(Filter::Text(id, TextFilterPB { condition, content }))
                }
                1 => {
                    use NumberFilterConditionPB::*;
                    let condition = match n {
                        0 => Equal,
                        1 => NotEqual,
                        2 => GreaterThan,
                        3 => LessThan,
                        4 => GreaterThanOrEqualTo,
                        5 => LessThanOrEqualTo,
                        6 => NumberIsEmpty,
                        7 => NumberIsNotEmpty,
                        _ => return Err("UNSUPPORTED_FILTER_CONDITION".into()),
                    };
                    if n < 6 && Decimal::from_str(&content).is_err() {
                        return Err("INVALID_NUMBER_FILTER".into());
                    }
                    Ok(Filter::Number(id, NumberFilterPB { condition, content }))
                }
                2 => {
                    let (filter, zone) = crate::date_filters::parse(f, n, &content)?;
                    Ok(Filter::Date(id, filter, zone))
                }
                5 if (0..=1).contains(&n) && content.is_empty() => Ok(Filter::Check(id, n == 0)),
                3 | 4 => {
                    use SelectOptionFilterConditionPB::*;
                    let condition = match n {
                        0 => OptionIs,
                        1 => OptionIsNot,
                        2 => OptionContains,
                        3 => OptionDoesNotContain,
                        4 => OptionIsEmpty,
                        5 => OptionIsNotEmpty,
                        _ => return Err("UNSUPPORTED_FILTER_CONDITION".into()),
                    };
                    let option_ids: Vec<String> = if content.is_empty() {
                        vec![]
                    } else {
                        content.split(',').map(str::to_string).collect()
                    };
                    let options = choices::options(f).ok_or("UNSUPPORTED_RULE_FIELD")?;
                    let mut unique = HashSet::new();
                    if option_ids.iter().any(|id| {
                        !unique.insert(id) || !options.options.iter().any(|o| &o.id == id)
                    }) || (n < 4 && option_ids.is_empty())
                    {
                        return Err("INVALID_OPTION_FILTER".into());
                    }
                    Ok(Filter::Select(
                        id,
                        SelectOptionFilterPB {
                            condition,
                            option_ids,
                        },
                    ))
                }
                _ => Err("UNSUPPORTED_FILTER_CONDITION".into()),
            }
        }
        _ => Err("UNSUPPORTED_FILTER_NODE".into()),
    }
}
fn raw_cell(row: &Value, id: &str) -> Result<Option<Cell>> {
    let v = &row["cells"][id]["raw"];
    if v.is_null() {
        return Ok(None);
    }
    serde_json::from_value(v.clone())
        .map(Some)
        .map_err(|_| "INVALID_RULE_CELL".into())
}
fn validate_cell(row: &Value, f: &Field) -> Result<()> {
    let raw = &row["cells"][&f.id]["raw"];
    let cell = raw_cell(row, &f.id)?;
    if model::logical_cell(cell.as_ref()).is_none() {
        return Ok(());
    }
    if raw["field_type"].as_i64() != Some(f.field_type) {
        return Err("UNRESOLVED_RULE_CELL".into());
    }
    if matches!(f.field_type, 0 | 1 | 3 | 4 | 5 | 6) {
        if raw.get("data").is_some_and(|v| !v.is_string()) {
            return Err("INVALID_RULE_CELL".into());
        }
        if f.field_type == 5
            && raw.get("data").is_some_and(|v| {
                !matches!(
                    v.as_str().unwrap_or("").to_lowercase().as_str(),
                    "true" | "false" | "1" | "0" | "yes" | "no" | ""
                )
            })
        {
            return Err("INVALID_RULE_CELL".into());
        }
    }
    Ok(())
}
fn text(row: &Value, id: &str) -> Result<String> {
    match &row["cells"][id]["value"] {
        Value::Null => Ok(String::new()),
        Value::String(s) => Ok(s.clone()),
        _ => Err("INVALID_RULE_CELL".into()),
    }
}
fn number_options(f: &Field) -> Result<NumberTypeOption> {
    from_any(&Any::from(f.get_any_type_option(1).unwrap_or_default()))
        .map_err(|_| "UNSUPPORTED_RULE_FIELD".into())
}
impl Filter {
    fn references<'a>(&'a self, fields: &mut HashSet<&'a str>) {
        match self {
            Self::Group(_, children) => {
                for child in children {
                    child.references(fields);
                }
            }
            Self::Text(id, _)
            | Self::Number(id, _)
            | Self::Check(id, _)
            | Self::Select(id, _)
            | Self::Date(id, _, _) => {
                fields.insert(id);
            }
        }
    }
    fn visible(&self, row: &Value, fields: &[Field]) -> Result<Option<bool>> {
        Ok(Some(match self {
            Self::Group(and, children) => {
                let values = children
                    .iter()
                    .map(|c| c.visible(row, fields))
                    .collect::<Result<Vec<_>>>()?;
                let values = values.into_iter().flatten().collect::<Vec<_>>();
                if values.is_empty() {
                    return Ok(None);
                }
                if *and {
                    values.into_iter().all(|v| v)
                } else {
                    values.into_iter().any(|v| v)
                }
            }
            Self::Text(id, f) => f.is_visible(text(row, id)?),
            Self::Check(id, checked) => {
                let value = &row["cells"][id]["value"];
                if !value.is_null() && !value.is_boolean() {
                    return Err("INVALID_RULE_CELL".into());
                }
                value.as_bool().unwrap_or(false) == *checked
            }
            Self::Number(id, filter) => {
                let f = fields.iter().find(|f| &f.id == id).ok_or("FIELD_MISSING")?;
                let cell = raw_cell(row, id)?;
                let raw = cell
                    .as_ref()
                    .and_then(|c| c.get("data"))
                    .and_then(|a| {
                        if let Any::String(s) = a {
                            Some(s.as_ref())
                        } else {
                            None
                        }
                    })
                    .unwrap_or("");
                crate::numbers::input(f, cell.as_ref()).ok_or("UNRESOLVED_RULE_CELL")?;
                let format = number_options(f)?
                    .format_cell_data(raw)
                    .map_err(|_| "INVALID_RULE_CELL")?;
                if !raw.is_empty() && format.decimal().is_none() {
                    return Err("INVALID_RULE_CELL".into());
                }
                filter.is_visible(&format).ok_or("INVALID_NUMBER_FILTER")?
            }
            Self::Date(id, filter, zone) => {
                let f = fields.iter().find(|f| &f.id == id).ok_or("FIELD_MISSING")?;
                return crate::date_filters::visible(f, filter, *zone, raw_cell(row, id)?.as_ref());
            }
            Self::Select(id, filter) => {
                let f = fields.iter().find(|f| &f.id == id).ok_or("FIELD_MISSING")?;
                let cell = raw_cell(row, id)?;
                if choices::unresolved(f, cell.as_ref()) {
                    return Err("UNRESOLVED_RULE_CELL".into());
                }
                let selected = choices::selected(f, cell.as_ref()).unwrap_or_default();
                let options = choices::options(f).ok_or("UNSUPPORTED_RULE_FIELD")?;
                let values = options
                    .options
                    .into_iter()
                    .filter(|o| selected.contains(&o.id))
                    .collect::<Vec<_>>();
                filter.is_visible(&values).ok_or("INVALID_OPTION_FILTER")?
            }
        }))
    }
}
#[derive(Eq, PartialEq, Ord, PartialOrd)]
enum Key {
    Text(String),
    Number(Decimal),
    Time(i64),
    Check(bool),
    Options(Vec<usize>),
}
fn sort_key(row: &Value, f: &Field) -> Result<Option<Key>> {
    let cell = raw_cell(row, &f.id)?;
    if f.field_type == 5 && model::logical_cell(cell.as_ref()).is_none() {
        return Ok(Some(Key::Check(false)));
    }
    if model::logical_cell(cell.as_ref()).is_none() {
        return Ok(None);
    }
    Ok(match f.field_type {
        0 | 6 => {
            let t = text(row, &f.id)?;
            if t.is_empty() {
                None
            } else {
                Some(Key::Text(t))
            }
        }
        1 => {
            let raw = cell
                .as_ref()
                .and_then(|c| c.get("data"))
                .and_then(|a| {
                    if let Any::String(s) = a {
                        Some(s.as_ref())
                    } else {
                        None
                    }
                })
                .ok_or("INVALID_RULE_CELL")?;
            crate::numbers::input(f, cell.as_ref()).ok_or("UNRESOLVED_RULE_CELL")?;
            let format = number_options(f)?
                .format_cell_data(raw)
                .map_err(|_| "INVALID_RULE_CELL")?;
            if !raw.is_empty() && format.decimal().is_none() {
                return Err("INVALID_RULE_CELL".into());
            }
            format.decimal().map(Key::Number)
        }
        2 => {
            if crate::dates::unresolved(f, cell.as_ref()) {
                return Err("UNRESOLVED_RULE_CELL".into());
            }
            cell.as_ref()
                .and_then(|c| DateCellData::from(c).timestamp)
                .map(Key::Time)
        }
        3 | 4 => {
            if choices::unresolved(f, cell.as_ref()) {
                return Err("UNRESOLVED_RULE_CELL".into());
            }
            let selected = choices::selected(f, cell.as_ref()).unwrap_or_default();
            let options = choices::options(f).ok_or("UNSUPPORTED_RULE_FIELD")?;
            // SiYuan's declared option order; preserve selected order and use
            // strict lexicographic length tie-breaking (not Go prefix-equals).
            let ranks = selected
                .iter()
                .map(|id| {
                    options
                        .options
                        .iter()
                        .position(|o| &o.id == id)
                        .ok_or("UNRESOLVED_RULE_CELL")
                })
                .collect::<std::result::Result<Vec<_>, _>>()?;
            if ranks.is_empty() {
                None
            } else {
                Some(Key::Options(ranks))
            }
        }
        5 => Some(Key::Check(
            row["cells"][&f.id]["value"]
                .as_bool()
                .ok_or("INVALID_RULE_CELL")?,
        )),
        _ => return Err("UNSUPPORTED_RULE_FIELD".into()),
    })
}
pub fn maps(value: Value) -> Result<Vec<HashMap<String, Any>>> {
    serde_json::from_value(value).map_err(|_| "INVALID_VIEW_RULE".into())
}
