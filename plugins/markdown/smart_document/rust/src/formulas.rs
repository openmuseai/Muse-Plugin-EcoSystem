//! Original AppFlowy math_equation/formula schema. Opaque TeX source stays in
//! the original block; the UI renderer and its limits do not rewrite content.
use crate::{Result, err, field, insert_node};
use collab_document::{
    blocks::{Block, DocumentData},
    document::Document,
};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
const STORED_LIMIT: usize = 65536;
const INPUT_LIMIT: usize = 8192;
fn source(block: &Block) -> Result<&str> {
    block
        .data
        .get("formula")
        .and_then(Value::as_str)
        .ok_or_else(|| "INVALID_FORMULA".into())
}
fn hash(value: &str) -> String {
    format!("{:x}", Sha256::digest(serde_json::to_vec(value).unwrap()))
}
pub fn validate(block: &Block, data: &DocumentData) -> Result<()> {
    let formula = source(block)?;
    if formula.len() > STORED_LIMIT
        || formula.contains('\0')
        || block.data.contains_key("delta")
        || block.external_id.is_some()
        || block.external_type.is_some()
        || data
            .meta
            .children_map
            .get(&block.children)
            .is_some_and(|v| !v.is_empty())
    {
        return Err("INVALID_FORMULA_BLOCK".into());
    }
    Ok(())
}
pub fn state(doc: &Document, id: &str) -> Result<Value> {
    let block = doc
        .get_block(id)
        .filter(|b| b.ty == "math_equation")
        .ok_or("FORMULA_MISSING")?;
    let formula = source(&block)?;
    Ok(json!({"blockId":id,"formula":formula,"hash":hash(formula)}))
}
pub fn insert(doc: &mut Document, op: &Value) -> Result<()> {
    let formula = field(op, "formula")?;
    if formula.len() > INPUT_LIMIT || formula.contains('\0') {
        return Err("FORMULA_INPUT_LIMIT".into());
    }
    let id = field(op, "blockId")?;
    if id.is_empty() || id.len() > 128 || id.chars().any(char::is_control) {
        return Err("INVALID_BLOCK_ID".into());
    }
    let data = crate::images::project(doc)?;
    let previous = match op.get("afterBlockId") {
        Some(value) => {
            let id = value.as_str().ok_or("INVALID_BLOCK_ID")?;
            let b = data.blocks.get(id).ok_or("TARGET_MISSING")?;
            if b.parent != data.page_id {
                return Err("ROOT_ANCHOR_REQUIRED".into());
            }
            Some(id.to_string())
        }
        None => data
            .meta
            .children_map
            .get(&data.blocks[&data.page_id].children)
            .and_then(|v| v.last())
            .cloned(),
    };
    insert_node(
        doc,
        &json!({"id":id,"type":"math_equation","data":{"formula":formula}}),
        &data.page_id,
        previous,
    )?;
    Ok(())
}
pub fn update(doc: &mut Document, op: &Value, remove: bool) -> Result<()> {
    let id = field(op, "blockId")?;
    let mut block = doc
        .get_block(id)
        .filter(|b| b.ty == "math_equation")
        .ok_or("FORMULA_MISSING")?;
    if hash(source(&block)?) != field(op, "expectedHash")? {
        return Err("FORMULA_CHANGED".into());
    }
    if remove {
        doc.delete_block(id).map_err(err)?;
        return Ok(());
    }
    let formula = field(op, "formula")?;
    if formula.len() > INPUT_LIMIT || formula.contains('\0') {
        return Err("FORMULA_INPUT_LIMIT".into());
    }
    block.data.insert("formula".into(), json!(formula));
    doc.update_block(id, block.data).map_err(err)?;
    Ok(())
}
