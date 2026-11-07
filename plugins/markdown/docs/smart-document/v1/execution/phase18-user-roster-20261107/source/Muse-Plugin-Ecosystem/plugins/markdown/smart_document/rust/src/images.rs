//! Versioned image references, owned metadata and insertion replay protection.
//! Bytes/authorization stay in the asset repository, outside the document CRDT.
use super::{Result, err, field, insert_node};
use collab::core::origin::CollabOrigin;
use collab::preclude::{Map, MapExt, MapRef, Transact};
use collab_document::{
    blocks::{Block, DocumentData},
    document::Document,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};

pub fn validate(block: &Block, data: &DocumentData) -> Result<()> {
    if block.external_id.is_some()
        || block.data.contains_key("delta")
        || data
            .meta
            .children_map
            .get(&block.children)
            .is_some_and(|c| !c.is_empty())
    {
        return Err("INVALID_IMAGE_BLOCK".into());
    }
    let asset = block.data.get("asset").ok_or("IMAGE_ASSET_REQUIRED")?;
    let fields = [
        "version",
        "provider",
        "scope",
        "owner",
        "key",
        "mediaType",
        "byteLength",
        "sha256",
    ];
    let values = asset.as_object().ok_or("INVALID_IMAGE_ASSET")?;
    if values.len() != fields.len()
        || !values.keys().all(|k| fields.contains(&k.as_str()))
        || asset.get("version").and_then(Value::as_u64) != Some(1)
    {
        return Err("INVALID_IMAGE_ASSET".into());
    }
    let provider = field(asset, "provider")?;
    let scope = field(asset, "scope")?;
    let owner = field(asset, "owner")?;
    uuid::Uuid::parse_str(owner).map_err(|_| "INVALID_ASSET_OWNER")?;
    if provider == "appflowy.private-assets/1" {
        uuid::Uuid::parse_str(scope).map_err(|_| "INVALID_ASSET_SCOPE")?;
    } else if provider != "muse.local-assets/1" {
        return Err("UNSUPPORTED_ASSET_PROVIDER".into());
    }
    if scope.len() > 256 || scope.chars().any(char::is_control) {
        return Err("INVALID_ASSET_SCOPE".into());
    }
    let digest = field(asset, "sha256")?;
    if digest.len() != 64
        || !digest
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        || field(asset, "key")? != digest
    {
        return Err("INVALID_ASSET_DIGEST".into());
    }
    if !["image/png", "image/jpeg", "image/gif", "image/webp"].contains(&field(asset, "mediaType")?)
    {
        return Err("UNSUPPORTED_IMAGE_TYPE".into());
    }
    let length = asset
        .get("byteLength")
        .and_then(Value::as_u64)
        .ok_or("INVALID_ASSET_SIZE")?;
    if length == 0 || length > 12 * 1024 * 1024 {
        return Err("INVALID_ASSET_SIZE".into());
    }
    if block.data.get("url").and_then(Value::as_str)
        != Some(format!("muse-asset://{owner}/{digest}").as_str())
    {
        return Err("INVALID_IMAGE_SOURCE".into());
    }
    for key in ["width", "height"] {
        if let Some(v) = block.data.get(key).filter(|v| !v.is_null()) {
            let n = v.as_f64().ok_or("INVALID_IMAGE_DIMENSION")?;
            if !n.is_finite() || n < 1.0 || n > 20000.0 {
                return Err("INVALID_IMAGE_DIMENSION".into());
            }
        }
    }
    if let Some(align) = block.data.get("align") {
        if ![Some("left"), Some("center"), Some("right")].contains(&align.as_str()) {
            return Err("INVALID_IMAGE_ALIGNMENT".into());
        }
    }
    for key in ["alt", "title"] {
        if let Some(v) = block.data.get(key) {
            let s = v.as_str().ok_or("INVALID_IMAGE_DESCRIPTION")?;
            if s.len() > 8192 || s.contains('\0') {
                return Err("INVALID_IMAGE_DESCRIPTION".into());
            }
        }
    }
    Ok(())
}

pub fn insert(doc: &mut Document, command: &Value) -> Result<()> {
    let node = command.get("node").ok_or("INVALID_IMAGE_BLOCK")?;
    if field(node, "type")? != "image" {
        return Err("INVALID_IMAGE_BLOCK".into());
    }
    let id = field(node, "id")?;
    if id.len() > 128 {
        return Err("INVALID_BLOCK_ID".into());
    }
    let fingerprint = format!(
        "{:x}",
        Sha256::digest(serde_json::to_vec(node).map_err(err)?)
    );
    let meta = meta(doc)?;
    let receipt_key = key(id, "receipt");
    {
        let txn = doc.transact();
        if let Some(previous) = meta.get_with_txn::<_, String>(&txn, &receipt_key) {
            if previous != fingerprint {
                return Err("IDEMPOTENCY_CONFLICT".into());
            }
            return Ok(());
        }
    }
    let data = doc.get_document_data().map_err(err)?;
    let previous = if let Some(after) = command.get("afterBlockId").and_then(Value::as_str) {
        let target = data.blocks.get(after).ok_or("TARGET_MISSING")?;
        if target.parent != data.page_id {
            return Err("ROOT_ANCHOR_REQUIRED".into());
        }
        Some(after.to_string())
    } else {
        data.meta
            .children_map
            .get(&data.blocks[&data.page_id].children)
            .and_then(|c| c.last())
            .cloned()
    };
    insert_node(doc, node, &data.page_id, previous)?;
    // Receipt must survive human undo/deletion, so an interrupted draft cleanup
    // cannot resurrect an image the author deliberately removed. No separate
    // file is committed between insertion and receipt in the synchronous core.
    let mut txn = doc.doc().transact_mut_with(CollabOrigin::Server);
    meta.insert(&mut txn, receipt_key, fingerprint);
    Ok(())
}

fn meta(doc: &Document) -> Result<MapRef> {
    let txn = doc.transact();
    let root: MapRef = doc
        .data
        .get_with_txn(&txn, "document")
        .ok_or("MISSING_ROOT")?;
    root.get_with_txn(&txn, "meta").ok_or("MISSING_META".into())
}
fn key(id: &str, property: &str) -> String {
    format!("muse.image.v1:{}", json!([id, property]))
}

/// Per-property CRDT registers in the existing shared metadata map. Width/height
/// and asset/url are atomic pairs; unrelated caption/size/align edits commute.
/// No concurrent creation of nested maps (which would overwrite one another).
pub fn project(doc: &Document) -> Result<DocumentData> {
    let mut data = doc.get_document_data().map_err(err)?;
    let meta = meta(doc)?;
    let txn = doc.transact();
    for block in data.blocks.values_mut().filter(|b| b.ty == "image") {
        for property in ["title", "alt", "align", "size", "source"] {
            if let Some(encoded) = meta.get_with_txn::<_, String>(&txn, &key(&block.id, property)) {
                let value: Value = serde_json::from_str(&encoded).map_err(err)?;
                if property == "size" || property == "source" {
                    let pair = value.as_object().ok_or("INVALID_IMAGE_PROPERTY")?;
                    let fields = if property == "size" {
                        ["width", "height"]
                    } else {
                        ["asset", "url"]
                    };
                    if pair.len() != 2 || !pair.keys().all(|k| fields.contains(&k.as_str())) {
                        return Err("INVALID_IMAGE_PROPERTY".into());
                    }
                    for (k, v) in pair {
                        if v.is_null() {
                            block.data.remove(k);
                        } else {
                            block.data.insert(k.clone(), v.clone());
                        }
                    }
                } else if value.is_null() {
                    block.data.remove(property);
                } else {
                    block.data.insert(property.into(), value);
                }
            }
        }
    }
    Ok(data)
}
pub fn update(doc: &mut Document, id: &str, patch: &serde_json::Map<String, Value>) -> Result<()> {
    let data = project(doc)?;
    let block = data.blocks.get(id).ok_or("TARGET_MISSING")?;
    if block.ty != "image" {
        return Err("NOT_IMAGE".into());
    }
    let mut updated = block.data.clone();
    for (key, value) in patch {
        if !["asset", "url", "width", "height", "alt", "title", "align"].contains(&key.as_str()) {
            return Err("UNSUPPORTED_IMAGE_PROPERTY".into());
        }
        updated.insert(key.clone(), value.clone());
    }
    // The upstream image resize gesture emits width only. Preserve the original
    // aspect ratio as one atomic size register rather than stretching height.
    if patch.contains_key("width") && !patch.contains_key("height") {
        if let (Some(width), Some(old_width), Some(old_height)) = (
            patch.get("width").and_then(Value::as_f64),
            block.data.get("width").and_then(Value::as_f64),
            block.data.get("height").and_then(Value::as_f64),
        ) {
            updated.insert("height".into(), json!(width * old_height / old_width));
        }
    }
    let mut properties = vec![];
    for property in ["title", "alt", "align"] {
        if let Some(value) = patch.get(property) {
            properties.push((property, value.clone()));
        }
    }
    for (property, fields) in [("size", ["width", "height"]), ("source", ["asset", "url"])] {
        if fields.iter().any(|field| patch.contains_key(*field)) {
            properties.push((
                property,
                json!({fields[0]:updated.get(fields[0]),fields[1]:updated.get(fields[1])}),
            ));
        }
    }
    let meta = meta(doc)?;
    let mut txn = doc.transact_mut();
    for (property, value) in properties {
        meta.insert(&mut txn, key(id, property), value.to_string());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{B64, Session};
    use base64::Engine;
    fn new() -> Session {
        Session::open(&uuid::Uuid::new_v4().to_string(), None).unwrap()
    }
    fn command(s: &Session) -> Value {
        let hash = "a".repeat(64);
        json!({"op":"insert_image","node":{"id":"image-a","type":"image","data":{
            "asset":{"version":1,"provider":"appflowy.private-assets/1","scope":uuid::Uuid::new_v4().to_string(),"owner":s.object_id,"key":hash,"mediaType":"image/png","byteLength":100,"sha256":hash},
            "url":format!("muse-asset://{}/{hash}",s.object_id),"width":320,"height":160,"align":"center","title":"","alt":""}}})
    }
    #[test]
    fn image_reference_validation_is_atomic_and_does_not_create_text() {
        let mut a = new();
        let mut op = command(&a);
        let before = a.snapshot().unwrap();
        op["node"]["data"]["url"] = json!("https://public.example/private.png");
        assert!(a.operations(&[op]).is_err());
        assert_eq!(a.snapshot().unwrap(), before);
        let op = command(&a);
        let state = a.operations(&[op]).unwrap();
        let block = &state["data"]["blocks"]["image-a"];
        assert!(block["external_id"].is_null());
        assert_eq!(block["data"]["asset"]["version"], 1);
        assert!(state["docState"].as_str().unwrap().len() < 10000);
    }
    #[test]
    fn upload_replay_after_undo_or_reopen_never_resurrects_image() {
        let mut a = new();
        let op = command(&a);
        a.operations(&[op.clone()]).unwrap();
        a.history(false).unwrap();
        assert!(!project(&a.doc).unwrap().blocks.contains_key("image-a"));
        a.operations(&[op.clone()]).unwrap();
        assert!(!project(&a.doc).unwrap().blocks.contains_key("image-a"));
        let bytes = B64
            .decode(a.snapshot().unwrap()["docState"].as_str().unwrap())
            .unwrap();
        let mut b = Session::open(&a.object_id, Some(bytes)).unwrap();
        b.operations(&[op.clone()]).unwrap();
        assert!(!project(&b.doc).unwrap().blocks.contains_key("image-a"));
        let mut conflict = op;
        conflict["node"]["data"]["title"] = json!("changed");
        assert_eq!(
            b.operations(&[conflict]).unwrap_err(),
            "IDEMPOTENCY_CONFLICT"
        );
    }
    #[test]
    fn concurrent_caption_and_size_commute_and_origin_undo_preserves_peer() {
        let mut a = new();
        a.operations(&[command(&a)]).unwrap();
        let mut b = Session::open(
            &a.object_id,
            Some(a.doc.encode_collab().unwrap().doc_state.to_vec()),
        )
        .unwrap();
        a.operations(&[json!({"op":"update_image","blockId":"image-a","attributes":{"title":"甲说明😀","alt":"内容"}})]).unwrap();
        b.operations(&[json!({"op":"update_image","blockId":"image-a","attributes":{"width":640,"align":"left"}})]).unwrap();
        let ua = a.doc.encode_collab().unwrap().doc_state.to_vec();
        let ub = b.doc.encode_collab().unwrap().doc_state.to_vec();
        a.apply_update(&ub).unwrap();
        b.apply_update(&ua).unwrap();
        assert_eq!(project(&a.doc).unwrap(), project(&b.doc).unwrap());
        let state = a.snapshot().unwrap();
        assert_eq!(
            state["data"]["blocks"]["image-a"]["data"]["title"],
            "甲说明😀"
        );
        assert_eq!(state["data"]["blocks"]["image-a"]["data"]["width"], 640);
        a.history(false).unwrap();
        let state = a.snapshot().unwrap();
        assert_eq!(state["data"]["blocks"]["image-a"]["data"]["title"], "");
        assert_eq!(state["data"]["blocks"]["image-a"]["data"]["width"], 640);
        let reopened = Session::open(
            &a.object_id,
            Some(a.doc.encode_collab().unwrap().doc_state.to_vec()),
        )
        .unwrap();
        assert_eq!(
            a.snapshot().unwrap()["data"],
            reopened.snapshot().unwrap()["data"]
        );
    }
}
