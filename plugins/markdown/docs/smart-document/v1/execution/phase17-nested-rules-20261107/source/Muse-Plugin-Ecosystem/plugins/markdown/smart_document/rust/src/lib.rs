//! Thin domain boundary over the exact AppFlowy-Collab revision used by Muse Cloud.
//! The editor is a projection; only this Document owns collaborative content.
use std::collections::{HashMap, HashSet};
#[cfg(not(target_arch = "wasm32"))]
use std::ffi::{CStr, CString, c_char};
use std::sync::{LazyLock, Mutex};

use base64::{Engine, engine::general_purpose::STANDARD as B64};
use collab::core::collab::{DataSource, default_client_id};
use collab::core::origin::CollabOrigin;
use collab::preclude::{Map, MapExt, MapRef, Transact, Update, updates::decoder::Decode};
use collab_document::blocks::{Block, DocumentData};
use collab_document::document::Document;
use collab_document::document_data::default_document_data;
use serde_json::{Value, json};
use uuid::Uuid;
mod embeds;
#[cfg(test)]
mod embeds_tests;
mod images;
mod links;

pub const COLLAB_REV: &str = "e59260e524f33104b0ddcd6bb8f6218cad0f7e18";
const MAX_BYTES: usize = 8 * 1024 * 1024;
static SESSIONS: LazyLock<Mutex<HashMap<String, Session>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub struct Session {
    doc: Document,
    client_id: u64,
    object_id: String,
    revision: u64,
}

type Result<T> = std::result::Result<T, String>;
fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}
fn field<'a>(v: &'a Value, name: &str) -> Result<&'a str> {
    v.get(name)
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| format!("INVALID_REQUEST:{name}"))
}
fn decode(s: &str) -> Result<Vec<u8>> {
    if s.len() > MAX_BYTES * 2 {
        return Err("QUOTA_EXCEEDED".into());
    }
    B64.decode(s).map_err(err)
}

impl Session {
    pub fn open(object_id: &str, doc_state: Option<Vec<u8>>) -> Result<Self> {
        Uuid::parse_str(object_id).map_err(|_| "INVALID_OBJECT_ID")?;
        let client_id = default_client_id();
        let mut doc = match doc_state {
            Some(bytes) => Document::open_with_options(
                CollabOrigin::Empty,
                DataSource::DocStateV1(bytes),
                object_id,
                client_id,
            )
            .map_err(err)?,
            None => Document::create(object_id, default_document_data(object_id), client_id)
                .map_err(err)?,
        };
        validate(&images::project(&doc)?)?;
        doc.enable_undo_redo();
        Ok(Self {
            doc,
            client_id,
            object_id: object_id.into(),
            revision: 0,
        })
    }

    fn candidate(&self) -> Result<Document> {
        Document::open_with_options(
            CollabOrigin::Empty,
            DataSource::DocStateV1(self.doc.encode_collab().map_err(err)?.doc_state.to_vec()),
            &self.object_id,
            self.client_id,
        )
        .map_err(err)
    }

    pub fn snapshot(&self) -> Result<Value> {
        let encoded = self.doc.encode_collab().map_err(err)?;
        Ok(
            json!({"profile":"muse.smart-document/phase1", "objectId":self.object_id,
            "revision":self.revision, "collabRevision":COLLAB_REV,
            "canUndo":self.doc.can_undo(), "canRedo":self.doc.can_redo(),
            "data":images::project(&self.doc)?,
            "docState":B64.encode(&encoded.doc_state),
            "stateVector":B64.encode(&encoded.state_vector),
            "encodedCollab":B64.encode(encoded.encode_to_bytes().map_err(err)?)}),
        )
    }

    // Validate on an isolated candidate before replacing live state, so failed multi-action
    // transactions and malformed remote updates cannot partially change the mounted document.
    pub fn operations(&mut self, ops: &[Value]) -> Result<Value> {
        if ops.len() > 256 {
            return Err("QUOTA_EXCEEDED".into());
        }
        let mut next = self.candidate()?;
        for op in ops {
            apply_operation(&mut next, op)?;
        }
        validate(&images::project(&next)?)?;
        validate_table_transition(&images::project(&self.doc)?, &images::project(&next)?)?;
        self.doc.undo_manager_mut().map_err(err)?.reset();
        for op in ops {
            apply_operation(&mut self.doc, op)?;
        }
        self.doc.undo_manager_mut().map_err(err)?.reset();
        self.revision += 1;
        self.snapshot()
    }

    pub fn apply_update(&mut self, bytes: &[u8]) -> Result<Value> {
        if bytes.is_empty() {
            let mut result = self.snapshot()?;
            result["changed"] = json!(false);
            return Ok(result);
        }
        if bytes.len() > MAX_BYTES {
            return Err("QUOTA_EXCEEDED".into());
        }
        let mut next = self.candidate()?;
        next.apply_update(Update::decode_v1(bytes).map_err(err)?)
            .map_err(err)?;
        validate(&images::project(&next)?)?;
        validate_table_transition(&images::project(&self.doc)?, &images::project(&next)?)?;
        let before = self.doc.encode_collab().map_err(err)?;
        let after = next.encode_collab().map_err(err)?;
        let changed =
            before.state_vector != after.state_vector || before.doc_state != after.doc_state;
        {
            let mut tx = self.doc.doc().transact_mut_with(CollabOrigin::Server);
            tx.apply_update(Update::decode_v1(bytes).map_err(err)?)
                .map_err(err)?;
        }
        if changed {
            self.revision += 1;
        }
        let mut result = self.snapshot()?;
        result["changed"] = json!(changed);
        Ok(result)
    }

    fn history(&mut self, redo: bool) -> Result<Value> {
        let mut backup = self.candidate()?;
        let changed = if redo {
            self.doc.redo()
        } else {
            self.doc.undo()
        };
        if let Err(error) = validate(&images::project(&self.doc)?) {
            backup.enable_undo_redo();
            self.doc = backup;
            return Err(error);
        }
        if changed {
            self.revision += 1;
        }
        self.snapshot()
    }

    fn sync_request(&self) -> Result<Value> {
        let c = self.doc.encode_collab().map_err(err)?;
        let request = muse_appflowy_wire::full_sync_request(
            &self.object_id,
            0,
            &c.state_vector,
            &c.doc_state,
            MAX_BYTES,
        )?;
        Ok(json!({"body":B64.encode(request)}))
    }
}

fn resolve(data: &DocumentData, path: &[Value]) -> Result<String> {
    let mut id = data.page_id.clone();
    for offset in path {
        let index = offset.as_u64().ok_or("INVALID_PATH")? as usize;
        let block = data.blocks.get(&id).ok_or("TARGET_MISSING")?;
        id = data
            .meta
            .children_map
            .get(&block.children)
            .and_then(|children| children.get(index))
            .ok_or("TARGET_MISSING")?
            .clone();
    }
    Ok(id)
}

fn apply_operation(doc: &mut Document, op: &Value) -> Result<()> {
    match field(op, "op")? {
        "insert_image" => return images::insert(doc, op),
        "update_image" => {
            return images::update(
                doc,
                field(op, "blockId")?,
                op.get("attributes")
                    .and_then(Value::as_object)
                    .ok_or("INVALID_ATTRIBUTES")?,
            );
        }
        _ => {}
    }
    if field(op, "op")? == "apply_link" {
        return links::apply(doc, op);
    }
    if field(op, "op")? == "set_type" {
        return set_block_type(doc, op);
    }
    let data = images::project(&doc)?;
    let path = op
        .get("path")
        .and_then(Value::as_array)
        .ok_or("INVALID_PATH")?;
    if path.is_empty() {
        return Err("ROOT_MUTATION_FORBIDDEN".into());
    }
    match field(op, "op")? {
        "update_text" => {
            let id = resolve(&data, path)?;
            let text_id = data
                .blocks
                .get(&id)
                .and_then(|b| b.external_id.as_ref())
                .ok_or("NOT_TEXT")?;
            let delta = op
                .get("delta")
                .and_then(Value::as_array)
                .ok_or("INVALID_DELTA")?;
            validate_delta(delta)?;
            let runs: Vec<Value> = serde_json::from_str(
                data.meta
                    .text_map
                    .as_ref()
                    .and_then(|texts| texts.get(text_id))
                    .map(String::as_str)
                    .unwrap_or("[]"),
            )
            .map_err(err)?;
            let text = runs
                .iter()
                .filter_map(|run| run.get("insert").and_then(Value::as_str))
                .collect::<String>();
            let mut boundaries = HashSet::from([0_u64]);
            let mut offset = 0_u64;
            for ch in text.chars() {
                offset += ch.len_utf16() as u64;
                boundaries.insert(offset);
            }
            let mut cursor = 0_u64;
            for run in delta {
                if let Some(length) = run
                    .get("retain")
                    .or_else(|| run.get("delete"))
                    .and_then(Value::as_u64)
                {
                    cursor = cursor.checked_add(length).ok_or("INVALID_TEXT_RANGE")?;
                    if !boundaries.contains(&cursor) {
                        return Err("INVALID_TEXT_RANGE".into());
                    }
                }
            }
            // AppFlowy uses UTF-16 offsets, matching Flutter Delta and preserving emoji boundaries.
            doc.apply_text_delta(text_id, serde_json::to_string(delta).map_err(err)?);
        }
        "insert" => {
            let parent = resolve(&data, &path[..path.len() - 1])?;
            let index = path.last().and_then(Value::as_u64).ok_or("INVALID_PATH")? as usize;
            let parent_block = data.blocks.get(&parent).ok_or("TARGET_MISSING")?;
            let children = data
                .meta
                .children_map
                .get(&parent_block.children)
                .cloned()
                .unwrap_or_default();
            if index > children.len() {
                return Err("INVALID_PATH".into());
            }
            let mut previous = if index == 0 {
                None
            } else {
                Some(children[index - 1].clone())
            };
            for node in op
                .get("nodes")
                .and_then(Value::as_array)
                .ok_or("INVALID_NODES")?
            {
                let id = insert_node(doc, node, &parent, previous)?;
                previous = Some(id);
            }
        }
        "delete" => {
            let count = op.get("count").and_then(Value::as_u64).unwrap_or(1);
            for _ in 0..count {
                let d = images::project(&doc)?;
                let id = resolve(&d, path)?;
                doc.delete_block(&id).map_err(err)?;
            }
        }
        "update" => {
            let id = resolve(&data, path)?;
            if data.blocks.get(&id).is_some_and(|b| b.ty == "image") {
                return images::update(
                    doc,
                    &id,
                    op.get("attributes")
                        .and_then(Value::as_object)
                        .ok_or("INVALID_ATTRIBUTES")?,
                );
            }
            let mut attrs = data.blocks.get(&id).ok_or("TARGET_MISSING")?.data.clone();
            let patch = op
                .get("attributes")
                .and_then(Value::as_object)
                .ok_or("INVALID_ATTRIBUTES")?;
            for (key, value) in patch {
                if key == "delta" {
                    return Err("USE_TEXT_DELTA".into());
                }
                if value.is_null() {
                    attrs.remove(key);
                } else {
                    attrs.insert(key.clone(), value.clone());
                }
            }
            doc.update_block(&id, attrs).map_err(err)?;
        }
        _ => return Err("UNSUPPORTED_OPERATION".into()),
    }
    Ok(())
}

// Additive domain command over the pinned AppFlowy wire schema. Change only
// ty/data in the existing Y.Map: block, children and Y.Text identities survive.
// The original editor's delete/insert conversion loses all three identities.
fn set_block_type(doc: &mut Document, op: &Value) -> Result<()> {
    let id = field(op, "blockId")?;
    let ty = field(op, "type")?;
    if ![
        "paragraph",
        "heading",
        "bulleted_list",
        "numbered_list",
        "todo_list",
        "quote",
        "code",
    ]
    .contains(&ty)
    {
        return Err("UNSUPPORTED_CONVERSION".into());
    }
    let data = images::project(&doc)?;
    if id == data.page_id {
        return Err("ROOT_MUTATION_FORBIDDEN".into());
    }
    let block = data.blocks.get(id).ok_or("TARGET_MISSING")?;
    if block.external_type.as_deref() != Some("text") {
        return Err("NOT_TEXT".into());
    }
    let mut attrs = block.data.clone();
    attrs.remove("level");
    attrs.remove("checked");
    if ty == "heading" {
        let level = match op.get("level") {
            None => 1,
            Some(value) => value.as_u64().ok_or("INVALID_HEADING_LEVEL")?,
        };
        if !(1..=6).contains(&level) {
            return Err("INVALID_HEADING_LEVEL".into());
        }
        attrs.insert("level".into(), json!(level));
    }
    if ty == "todo_list" {
        attrs.insert(
            "checked".into(),
            if block.ty == "todo_list" {
                block.data.get("checked").cloned().unwrap_or(json!(false))
            } else {
                json!(false)
            },
        );
    }
    // These are the same public Y.Map paths read by the pinned DocumentBody.
    // Keep the dependency unchanged and bind this adapter to COLLAB_REV.
    let block_map: MapRef = {
        let txn = doc.transact();
        let root: MapRef = doc
            .data
            .get_with_txn(&txn, "document")
            .ok_or("MISSING_ROOT")?;
        let blocks: MapRef = root.get_with_txn(&txn, "blocks").ok_or("MISSING_BLOCKS")?;
        blocks.get_with_txn(&txn, id).ok_or("TARGET_MISSING")?
    };
    let encoded = serde_json::to_string(&attrs).map_err(err)?;
    let mut txn = doc.transact_mut();
    block_map.insert(&mut txn, "ty", ty);
    block_map.insert(&mut txn, "data", encoded);
    Ok(())
}

fn validate_delta(delta: &[Value]) -> Result<()> {
    for item in delta {
        let m = item.as_object().ok_or("INVALID_DELTA")?;
        if m.keys()
            .any(|k| !["insert", "delete", "retain", "attributes"].contains(&k.as_str()))
        {
            return Err("INVALID_DELTA".into());
        }
        if ["insert", "delete", "retain"]
            .iter()
            .filter(|k| m.contains_key(**k))
            .count()
            != 1
        {
            return Err("INVALID_DELTA".into());
        }
        if let Some(v) = m.get("insert") {
            if !v.is_string() {
                return Err("UNSUPPORTED_INLINE_ATOM".into());
            }
        }
        for k in ["delete", "retain"] {
            if let Some(v) = m.get(k) {
                if v.as_u64().is_none() {
                    return Err("INVALID_DELTA".into());
                }
            }
        }
        if let Some(v) = m.get("attributes") {
            if !v.is_object() {
                return Err("INVALID_DELTA".into());
            }
            if let Some(href) = v.get("href") {
                links::validate_href(href)?;
            }
        }
    }
    Ok(())
}

fn insert_node(
    doc: &mut Document,
    node: &Value,
    parent: &str,
    previous: Option<String>,
) -> Result<String> {
    let id = field(node, "id")?.to_string();
    if doc.get_block(&id).is_some() {
        return Err("DUPLICATE_BLOCK_ID".into());
    }
    let ty = field(node, "type")?.to_string();
    if ![
        "paragraph",
        "heading",
        "bulleted_list",
        "numbered_list",
        "todo_list",
        "quote",
        "code",
        "divider",
        "table",
        "table/cell",
        "image",
        "grid",
        "board",
        "calendar",
    ]
    .contains(&ty.as_str())
    {
        return Err("UNSUPPORTED_ELEMENT".into());
    }
    let mut attrs: HashMap<String, Value> =
        serde_json::from_value(node.get("data").cloned().unwrap_or(json!({}))).map_err(err)?;
    let delta = attrs.remove("delta").unwrap_or(json!([]));
    validate_delta(delta.as_array().ok_or("INVALID_DELTA")?)?;
    let text_id = format!("text-{id}");
    let structural = matches!(
        ty.as_str(),
        "table" | "table/cell" | "image" | "grid" | "board" | "calendar"
    );
    let block = Block {
        id: id.clone(),
        ty,
        parent: parent.into(),
        children: format!("children-{id}"),
        external_id: (!structural).then_some(text_id.clone()),
        external_type: (!structural).then_some("text".into()),
        data: attrs,
    };
    doc.insert_block(block, previous).map_err(err)?;
    if !structural {
        doc.apply_text_delta(&text_id, delta.to_string());
    } else if delta.as_array().is_some_and(|runs| !runs.is_empty()) {
        return Err("STRUCTURAL_NODE_HAS_TEXT".into());
    }
    if let Some(children) = node.get("children").and_then(Value::as_array) {
        let mut prev = None;
        for child in children {
            prev = Some(insert_node(doc, child, &id, prev)?);
        }
    }
    Ok(id)
}

fn validate(data: &DocumentData) -> Result<()> {
    if data.blocks.len() > 10000 {
        return Err("QUOTA_EXCEEDED".into());
    }
    let root = data.blocks.get(&data.page_id).ok_or("MISSING_ROOT")?;
    if !root.parent.is_empty() || root.ty != "page" {
        return Err("INVALID_ROOT".into());
    }
    let mut seen = HashSet::new();
    let mut queue = vec![data.page_id.clone()];
    while let Some(id) = queue.pop() {
        if !seen.insert(id.clone()) {
            return Err("TREE_CYCLE_OR_MULTIPLE_PARENTS".into());
        }
        let block = data.blocks.get(&id).ok_or("MISSING_BLOCK")?;
        if block.ty == "image" {
            images::validate(block, data)?;
        }
        if matches!(block.ty.as_str(), "grid" | "board" | "calendar") {
            embeds::validate(block, data)?;
        }
        if let Some(text_id) = &block.external_id {
            if let Some(raw) = data.meta.text_map.as_ref().and_then(|m| m.get(text_id)) {
                let runs: Vec<Value> = serde_json::from_str(raw).map_err(err)?;
                validate_delta(&runs)?;
            }
        }
        if block.ty == "table" {
            validate_table(data, block)?;
        } else if block.ty == "table/cell"
            && data.blocks.get(&block.parent).map(|b| b.ty.as_str()) != Some("table")
        {
            return Err("ORPHAN_TABLE_CELL".into());
        }
        if let Some(children) = data.meta.children_map.get(&block.children) {
            for child in children {
                if data.blocks.get(child).ok_or("MISSING_BLOCK")?.parent != id {
                    return Err("INVALID_PARENT".into());
                }
                queue.push(child.clone());
            }
        }
    }
    if seen.len() != data.blocks.len() {
        return Err("UNREACHABLE_BLOCK".into());
    }
    Ok(())
}

// Versioned, fixed topology for this increment. Rendering never writes geometry.
// Cell text remains original AppFlowy Y.Text; mutable row/column topology is a
// separate future protocol and must not be enabled via upstream table actions.
fn validate_table(data: &DocumentData, table: &Block) -> Result<()> {
    if table.parent != data.page_id {
        return Err("TABLE_REQUIRES_ROOT".into());
    }
    if table.data.get("museTable").and_then(Value::as_str) != Some("fixed-grid/1") {
        return Err("UNSUPPORTED_TABLE_SCHEMA".into());
    }
    let rows = table
        .data
        .get("rowsLen")
        .and_then(Value::as_u64)
        .ok_or("INVALID_TABLE_SIZE")?;
    let cols = table
        .data
        .get("colsLen")
        .and_then(Value::as_u64)
        .ok_or("INVALID_TABLE_SIZE")?;
    if !(1..=20).contains(&rows) || !(1..=10).contains(&cols) {
        return Err("INVALID_TABLE_SIZE".into());
    }
    if table.external_id.is_some() {
        return Err("STRUCTURAL_NODE_HAS_TEXT".into());
    }
    let children = data
        .meta
        .children_map
        .get(&table.children)
        .ok_or("INVALID_TABLE_CELLS")?;
    if children.len() as u64 != rows * cols {
        return Err("INVALID_TABLE_CELLS".into());
    }
    let mut coordinates = HashSet::new();
    for id in children {
        let cell = data.blocks.get(id).ok_or("MISSING_BLOCK")?;
        let row = cell
            .data
            .get("rowPosition")
            .and_then(Value::as_u64)
            .ok_or("INVALID_TABLE_COORDINATE")?;
        let col = cell
            .data
            .get("colPosition")
            .and_then(Value::as_u64)
            .ok_or("INVALID_TABLE_COORDINATE")?;
        if cell.ty != "table/cell"
            || cell.external_id.is_some()
            || row >= rows
            || col >= cols
            || !coordinates.insert((row, col))
        {
            return Err("INVALID_TABLE_COORDINATE".into());
        }
        let content = data
            .meta
            .children_map
            .get(&cell.children)
            .ok_or("EMPTY_TABLE_CELL")?;
        if content.is_empty()
            || content.iter().any(|child| {
                data.blocks.get(child).is_none_or(|b| {
                    b.external_id.is_none()
                        || ![
                            "paragraph",
                            "heading",
                            "bulleted_list",
                            "numbered_list",
                            "todo_list",
                            "quote",
                            "code",
                        ]
                        .contains(&b.ty.as_str())
                        || data
                            .meta
                            .children_map
                            .get(&b.children)
                            .is_some_and(|children| !children.is_empty())
                })
            })
        {
            return Err("INVALID_TABLE_CELL_CONTENT".into());
        }
    }
    Ok(())
}

fn validate_table_transition(before: &DocumentData, after: &DocumentData) -> Result<()> {
    for old in before.blocks.values().filter(|b| b.ty == "table") {
        let Some(new) = after.blocks.get(&old.id) else {
            continue;
        }; // whole-table deletion
        if new.ty != "table"
            || ["museTable", "rowsLen", "colsLen"]
                .iter()
                .any(|key| old.data.get(*key) != new.data.get(*key))
            || before.meta.children_map.get(&old.children)
                != after.meta.children_map.get(&new.children)
        {
            return Err("TABLE_TOPOLOGY_READ_ONLY".into());
        }
        for id in before
            .meta
            .children_map
            .get(&old.children)
            .into_iter()
            .flatten()
        {
            let a = before.blocks.get(id).ok_or("MISSING_BLOCK")?;
            let b = after.blocks.get(id).ok_or("TABLE_TOPOLOGY_READ_ONLY")?;
            if ["rowPosition", "colPosition"]
                .iter()
                .any(|key| a.data.get(*key) != b.data.get(*key))
            {
                return Err("TABLE_TOPOLOGY_READ_ONLY".into());
            }
        }
    }
    Ok(())
}

pub fn call(request: Value) -> Result<Value> {
    let mut sessions = SESSIONS.lock().map_err(|_| "ENGINE_POISONED")?;
    let action = field(&request, "action")?;
    if action == "open" {
        let object = field(&request, "objectId")?;
        let state = request
            .get("docState")
            .and_then(Value::as_str)
            .map(decode)
            .transpose()?;
        let session = Session::open(object, state)?;
        let mut result = session.snapshot()?;
        let handle = Uuid::new_v4().to_string();
        result["handle"] = json!(handle);
        if sessions.len() >= 128 {
            return Err("SESSION_LIMIT".into());
        }
        sessions.insert(handle, session);
        return Ok(result);
    }
    let handle = field(&request, "handle")?;
    if action == "close" {
        sessions.remove(handle);
        return Ok(json!({"closed":true}));
    }
    let session = sessions.get_mut(handle).ok_or("SESSION_CLOSED")?;
    match action {
        "validateLink" => {
            links::validate_href(request.get("href").ok_or("INVALID_LINK")?)?;
            Ok(json!({"valid":true}))
        }
        "captureTextRange" => links::capture(&mut session.doc, &request),
        "resolveTextRange" => {
            let anchor = request.get("anchor").ok_or("INVALID_TEXT_ANCHOR")?;
            let (block, text, start, end) = links::resolve(&session.doc, anchor)?;
            Ok(json!({"blockId":block,"textId":text,"start":start,"end":end}))
        }
        "snapshot" => session.snapshot(),
        "undo" => session.history(false),
        "redo" => session.history(true),
        "operations" => session.operations(
            request
                .get("operations")
                .and_then(Value::as_array)
                .ok_or("INVALID_OPERATIONS")?,
        ),
        "applyUpdate" => session.apply_update(&decode(field(&request, "update")?)?),
        "syncRequest" => session.sync_request(),
        "applySync" => {
            let bytes = decode(field(&request, "body")?)?;
            let decompressed = muse_appflowy_wire::full_sync_response(&bytes, MAX_BYTES)?;
            session.apply_update(&decompressed)
        }
        _ => Err("UNSUPPORTED_ACTION".into()),
    }
}

/// Input is a NUL-terminated UTF-8 JSON string. The caller owns input; the caller
/// must release returned memory using muse_smart_document_free, even on errors.
#[cfg(not(target_arch = "wasm32"))]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn muse_smart_document_call(input: *const c_char) -> *mut c_char {
    if input.is_null() {
        return CString::new(r#"{"ok":false,"error":"NULL_REQUEST"}"#)
            .unwrap()
            .into_raw();
    }
    let raw = unsafe { CStr::from_ptr(input) }.to_bytes();
    CString::new(json_call(raw))
        .expect("JSON has no unescaped NUL")
        .into_raw()
}

fn json_call(raw: &[u8]) -> String {
    std::panic::catch_unwind(|| {
        if raw.len() > MAX_BYTES {
            return json!({"ok":false,"error":"QUOTA_EXCEEDED"});
        }
        let result = serde_json::from_slice(raw).map_err(err).and_then(call);
        match result {
            Ok(data) => json!({"ok":true,"data":data}),
            Err(error) => json!({"ok":false,"error":error}),
        }
    })
    .unwrap_or_else(|_| json!({"ok":false,"error":"ENGINE_FAILURE"}))
    .to_string()
}

#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub fn muse_smart_document_json(input: &str) -> String {
    json_call(input.as_bytes())
}

#[cfg(not(target_arch = "wasm32"))]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn muse_smart_document_free(output: *mut c_char) {
    if !output.is_null() {
        drop(unsafe { CString::from_raw(output) });
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn new() -> Session {
        Session::open(&Uuid::new_v4().to_string(), None).unwrap()
    }
    fn delta(items: Value) -> Value {
        json!({"op":"update_text","path":[0],"delta":items})
    }
    #[test]
    fn concurrent_offline_unicode_and_marks_converge() {
        let mut a = new();
        a.operations(&[delta(json!([{"insert":"中文😀"}]))])
            .unwrap();
        let base = a.doc.encode_collab().unwrap().doc_state.to_vec();
        let mut b = Session::open(&a.object_id, Some(base)).unwrap();
        a.operations(&[delta(json!([{"retain":4},{"insert":"甲"}]))])
            .unwrap();
        b.operations(&[delta(
            json!([{"retain":4},{"insert":"乙","attributes":{"bold":true}}]),
        )])
        .unwrap();
        let ua = a.doc.encode_collab().unwrap().doc_state.to_vec();
        let ub = b.doc.encode_collab().unwrap().doc_state.to_vec();
        a.apply_update(&ub).unwrap();
        b.apply_update(&ua).unwrap();
        assert_eq!(
            a.doc.get_document_data().unwrap(),
            b.doc.get_document_data().unwrap()
        );
        let text = a.doc.get_document_data().unwrap().meta.text_map.unwrap();
        let rendered = text.values().cloned().collect::<String>();
        assert!(rendered.contains("甲") && rendered.contains("乙") && rendered.contains("bold"));
        a.history(false).unwrap();
        let text = a
            .doc
            .get_document_data()
            .unwrap()
            .meta
            .text_map
            .unwrap()
            .values()
            .cloned()
            .collect::<String>();
        assert!(!text.contains("甲") && text.contains("乙") && text.contains("bold"));
        a.history(true).unwrap();
        assert_eq!(
            a.doc.get_document_data().unwrap(),
            b.doc.get_document_data().unwrap()
        );
    }
    #[test]
    fn invalid_batch_is_atomic_and_ids_survive_reopen() {
        let mut a = new();
        let before = a.doc.get_document_data().unwrap();
        assert!(
            a.operations(&[
                delta(json!([{"insert":"must rollback"}])),
                json!({"op":"bad","path":[0]})
            ])
            .is_err()
        );
        assert_eq!(a.doc.get_document_data().unwrap(), before);
        let state = a.doc.encode_collab().unwrap().doc_state.to_vec();
        let b = Session::open(&a.object_id, Some(state)).unwrap();
        assert_eq!(b.doc.get_document_data().unwrap(), before);
    }
    #[test]
    fn rejects_out_of_bounds_and_split_surrogate_without_poisoning_session() {
        let mut a = new();
        a.operations(&[delta(json!([{"insert":"中😀"}]))]).unwrap();
        let before = a.doc.get_document_data().unwrap();
        assert!(
            a.operations(&[delta(json!([{"retain":2},{"delete":1}]))])
                .is_err()
        );
        assert!(
            a.operations(&[delta(json!([{"retain":200},{"insert":"bad"}]))])
                .is_err()
        );
        assert_eq!(a.doc.get_document_data().unwrap(), before);
        a.operations(&[delta(json!([{"retain":3},{"insert":"安全"}]))])
            .unwrap();
    }
    #[test]
    fn stable_block_insert_delete_and_duplicate_update() {
        let mut a = new();
        a.operations(&[json!({"op":"insert","path":[1],"nodes":[{"id":"heading-one","type":"heading","data":{"level":1,"delta":[{"insert":"阶段一"}]}}]})]).unwrap();
        assert!(a.doc.get_block("heading-one").is_some());
        let update = a.doc.encode_collab().unwrap().doc_state.to_vec();
        a.apply_update(&update).unwrap();
        assert_eq!(a.doc.get_document_data().unwrap().blocks.len(), 3);
        a.operations(&[json!({"op":"delete","path":[1],"count":1})])
            .unwrap();
        assert!(a.doc.get_block("heading-one").is_none());
    }
    #[test]
    fn type_conversion_preserves_block_text_children_and_undo_identity() {
        let mut a = new();
        a.operations(&[delta(
            json!([{"insert":"稳定块😀","attributes":{"bold":true}}]),
        )])
        .unwrap();
        a.operations(&[json!({"op":"insert","path":[0,0],"nodes":[{"id":"nested-child","type":"paragraph","data":{"delta":[{"insert":"子块"}]}}]})]).unwrap();
        let before = a.doc.get_document_data().unwrap();
        let id = resolve(&before, &[json!(0)]).unwrap();
        let old = before.blocks[&id].clone();
        a.operations(&[json!({"op":"set_type","blockId":id,"type":"heading","level":6})])
            .unwrap();
        let after = a.doc.get_document_data().unwrap();
        assert_eq!(after.blocks[&id].external_id, old.external_id);
        assert_eq!(after.blocks[&id].children, old.children);
        assert_eq!(after.meta, before.meta);
        assert_eq!(after.blocks[&id].data["level"], json!(6));
        a.history(false).unwrap();
        assert_eq!(a.doc.get_block(&id).unwrap().ty, "paragraph");
        assert!(a.doc.get_block("nested-child").is_some());
        a.history(true).unwrap();
        let b = Session::open(
            &a.object_id,
            Some(a.doc.encode_collab().unwrap().doc_state.to_vec()),
        )
        .unwrap();
        assert_eq!(b.doc.get_document_data().unwrap(), after);
    }

    #[test]
    fn concurrent_type_and_remote_text_converge_without_losing_text_on_undo() {
        let mut a = new();
        a.operations(&[delta(json!([{"insert":"原文"}]))]).unwrap();
        let base = a.doc.encode_collab().unwrap().doc_state.to_vec();
        let id = resolve(&a.doc.get_document_data().unwrap(), &[json!(0)]).unwrap();
        let mut b = Session::open(&a.object_id, Some(base)).unwrap();
        a.operations(&[json!({"op":"set_type","blockId":id,"type":"heading","level":2})])
            .unwrap();
        b.operations(&[delta(
            json!([{"retain":2},{"insert":"远端😀","attributes":{"italic":true}}]),
        )])
        .unwrap();
        let ua = a.doc.encode_collab().unwrap().doc_state.to_vec();
        let ub = b.doc.encode_collab().unwrap().doc_state.to_vec();
        a.apply_update(&ub).unwrap();
        b.apply_update(&ua).unwrap();
        assert_eq!(
            a.doc.get_document_data().unwrap(),
            b.doc.get_document_data().unwrap()
        );
        a.history(false).unwrap();
        let after = a.doc.get_document_data().unwrap();
        assert_eq!(after.blocks[&id].ty, "paragraph");
        assert!(
            after
                .meta
                .text_map
                .unwrap()
                .values()
                .any(|text| text.contains("远端😀"))
        );
        b.apply_update(&a.doc.encode_collab().unwrap().doc_state.to_vec())
            .unwrap();
        assert_eq!(
            a.doc.get_document_data().unwrap(),
            b.doc.get_document_data().unwrap()
        );
    }

    #[test]
    fn invalid_conversion_batch_is_atomic_and_todo_completion_survives_reselection() {
        let mut a = new();
        let before = a.doc.get_document_data().unwrap();
        let id = resolve(&before, &[json!(0)]).unwrap();
        for level in [json!(0), json!(7), json!("bad")] {
            assert!(
                a.operations(&[
                    delta(json!([{"insert":"rollback"}])),
                    json!({"op":"set_type","blockId":id,"type":"heading","level":level})
                ])
                .is_err()
            );
            assert_eq!(a.doc.get_document_data().unwrap(), before);
        }
        assert!(
            a.operations(&[json!({"op":"set_type","blockId":before.page_id,"type":"paragraph"})])
                .is_err()
        );
        assert!(
            a.operations(&[json!({"op":"set_type","blockId":id,"type":"image"})])
                .is_err()
        );
        a.operations(&[
            json!({"op":"set_type","blockId":id,"type":"todo_list"}),
            json!({"op":"update","path":[0],"attributes":{"checked":true}}),
        ])
        .unwrap();
        a.operations(&[json!({"op":"set_type","blockId":id,"type":"todo_list"})])
            .unwrap();
        assert_eq!(a.doc.get_block(&id).unwrap().data["checked"], json!(true));
    }

    fn fixed_table() -> Value {
        json!({"id":"grid","type":"table","data":{"museTable":"fixed-grid/1","rowsLen":2,"colsLen":2},
          "children":(0..2).flat_map(|col| (0..2).map(move |row| json!({
            "id":format!("cell-{row}-{col}"),"type":"table/cell","data":{"rowPosition":row,"colPosition":col},
            "children":[{"id":format!("p-{row}-{col}"),"type":"paragraph","data":{"delta":[]}}]
          }))).collect::<Vec<_>>()})
    }
    fn add_table(a: &mut Session) {
        a.operations(&[json!({"op":"insert","path":[1],"nodes":[fixed_table()]})])
            .unwrap();
    }
    #[test]
    fn table_cell_concurrency_marks_origin_undo_and_reopen() {
        let mut a = new();
        add_table(&mut a);
        let before = a.doc.get_document_data().unwrap();
        let mut b = Session::open(
            &a.object_id,
            Some(a.doc.encode_collab().unwrap().doc_state.to_vec()),
        )
        .unwrap();
        a.operations(&[json!({"op":"update_text","path":[1,0,0],"delta":[{"insert":"甲😀","attributes":{"bold":true}}]})]).unwrap();
        b.operations(&[
            json!({"op":"update_text","path":[1,0,0],"delta":[{"insert":"乙","attributes":{"italic":true}}]}),
            json!({"op":"update_text","path":[1,3,0],"delta":[{"insert":"另一个单元格\n多行"}]}),
        ]).unwrap();
        let ua = a.doc.encode_collab().unwrap().doc_state.to_vec();
        let ub = b.doc.encode_collab().unwrap().doc_state.to_vec();
        a.apply_update(&ub).unwrap();
        b.apply_update(&ua).unwrap();
        assert_eq!(
            a.doc.get_document_data().unwrap(),
            b.doc.get_document_data().unwrap()
        );
        a.history(false).unwrap();
        let data = a.doc.get_document_data().unwrap();
        let text = &data.meta.text_map.as_ref().unwrap()["text-p-0-0"];
        assert!(text.contains("乙") && text.contains("italic") && !text.contains("甲"));
        for id in ["grid", "cell-0-0", "p-0-0", "p-1-1"] {
            assert_eq!(before.blocks[id], data.blocks[id]);
        }
        a.history(true).unwrap();
        let reopened = Session::open(
            &a.object_id,
            Some(a.doc.encode_collab().unwrap().doc_state.to_vec()),
        )
        .unwrap();
        assert_eq!(
            a.doc.get_document_data().unwrap(),
            reopened.doc.get_document_data().unwrap()
        );
    }
    #[test]
    fn table_invalid_grid_and_geometry_mutations_are_atomic() {
        let mut a = new();
        for rows in [json!(0), json!(21), json!("2")] {
            let mut table = fixed_table();
            table["data"]["rowsLen"] = rows;
            assert!(
                a.operations(&[json!({"op":"insert","path":[1],"nodes":[table]})])
                    .is_err()
            );
        }
        let mut duplicate = fixed_table();
        duplicate["children"][1]["data"]["rowPosition"] = json!(0);
        assert!(
            a.operations(&[json!({"op":"insert","path":[1],"nodes":[duplicate]})])
                .is_err()
        );
        let mut empty = fixed_table();
        empty["children"][0]["children"] = json!([]);
        assert!(
            a.operations(&[json!({"op":"insert","path":[1],"nodes":[empty]})])
                .is_err()
        );
        assert_eq!(a.doc.get_document_data().unwrap().blocks.len(), 2);
        add_table(&mut a);
        let before = a.snapshot().unwrap();
        // A dimensionally valid coordinate swap still violates fixed-grid identity.
        assert!(
            a.operations(&[
                json!({"op":"update","path":[1,0],"attributes":{"rowPosition":1}}),
                json!({"op":"update","path":[1,1],"attributes":{"rowPosition":0}})
            ])
            .unwrap_err()
            .contains("TABLE_TOPOLOGY_READ_ONLY")
        );
        assert!(
            a.operations(&[json!({"op":"delete","path":[1,0,0],"count":1})])
                .is_err()
        );
        assert_eq!(before, a.snapshot().unwrap());
        a.operations(&[json!({"op":"delete","path":[1],"count":1})])
            .unwrap();
        assert_eq!(a.doc.get_document_data().unwrap().blocks.len(), 2);
        a.history(false).unwrap();
        assert!(a.doc.get_block("grid").is_some());
    }
    #[test]
    fn malformed_remote_table_update_leaves_live_document_unchanged() {
        let mut a = new();
        add_table(&mut a);
        let mut remote = Session::open(
            &a.object_id,
            Some(a.doc.encode_collab().unwrap().doc_state.to_vec()),
        )
        .unwrap();
        remote
            .doc
            .update_block(
                "cell-0-0",
                HashMap::from([
                    ("rowPosition".into(), json!(99)),
                    ("colPosition".into(), json!(0)),
                ]),
            )
            .unwrap();
        let before = a.snapshot().unwrap();
        assert!(
            a.apply_update(&remote.doc.encode_collab().unwrap().doc_state)
                .is_err()
        );
        assert_eq!(a.snapshot().unwrap(), before);
    }
}
