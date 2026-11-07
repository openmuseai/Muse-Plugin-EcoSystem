//! Link commands adapt existing AppFlowy href marks and Yrs StickyIndex.
//! No independent rich-text model, editor selection path or network operation.
use super::{Result, decode, err, field};
use base64::{Engine, engine::general_purpose::STANDARD as B64};
use collab::preclude::branch::BranchPtr;
use collab::preclude::{
    Assoc, IndexedSequence, MapExt, MapRef, StickyIndex, TextRef,
    updates::{decoder::Decode, encoder::Encode},
};
use collab_document::document::Document;
use serde_json::{Value, json};

pub fn validate_href(value: &Value) -> Result<()> {
    if value.is_null() {
        return Ok(());
    }
    let href = value.as_str().ok_or("INVALID_LINK")?;
    if href.is_empty()
        || href.len() > 8192
        || href.chars().any(char::is_control)
        || href.trim() != href
    {
        return Err("INVALID_LINK".into());
    }
    let uri = url::Url::parse(href).map_err(|_| "INVALID_LINK")?;
    if !uri.username().is_empty() || uri.password().is_some() {
        return Err("LINK_CREDENTIALS_FORBIDDEN".into());
    }
    match uri.scheme() {
        "http" | "https" if uri.host_str().is_some() => Ok(()),
        "mailto" | "tel" if !uri.path().is_empty() => Ok(()),
        "siyuan" | "muse" if uri.host_str().is_some() => Ok(()),
        _ => Err("UNSUPPORTED_LINK_SCHEME".into()),
    }
}

fn text_ref(
    doc: &Document,
    block_id: &str,
    expected_text: Option<&str>,
) -> Result<(String, TextRef)> {
    let block = doc.get_block(block_id).ok_or("TARGET_MISSING")?;
    let id = block.external_id.ok_or("NOT_TEXT")?;
    if expected_text.is_some_and(|expected| expected != id) {
        return Err("TEXT_IDENTITY_CHANGED".into());
    }
    let txn = doc.transact();
    let root: MapRef = doc
        .data
        .get_with_txn(&txn, "document")
        .ok_or("MISSING_ROOT")?;
    let meta: MapRef = root.get_with_txn(&txn, "meta").ok_or("MISSING_META")?;
    let texts: MapRef = meta.get_with_txn(&txn, "text_map").ok_or("MISSING_TEXTS")?;
    let text: TextRef = texts.get_with_txn(&txn, &id).ok_or("NOT_TEXT")?;
    Ok((id, text))
}

fn slice(doc: &Document, block: &str, start: u32, end: u32) -> Result<String> {
    let text = doc.get_plain_text_from_block(block).ok_or("NOT_TEXT")?;
    let units: Vec<_> = text.encode_utf16().collect();
    for index in [start as usize, end as usize] {
        if index > 0
            && index < units.len()
            && (0xD800..=0xDBFF).contains(&units[index - 1])
            && (0xDC00..=0xDFFF).contains(&units[index])
        {
            return Err("INVALID_TEXT_RANGE".into());
        }
    }
    let range = units
        .get(start as usize..end as usize)
        .ok_or("INVALID_TEXT_RANGE")?;
    String::from_utf16(range).map_err(|_| "INVALID_TEXT_RANGE".into())
}

pub fn capture(doc: &mut Document, request: &Value) -> Result<Value> {
    let block = field(request, "blockId")?;
    let start = request
        .get("start")
        .and_then(Value::as_u64)
        .and_then(|n| u32::try_from(n).ok())
        .ok_or("INVALID_TEXT_RANGE")?;
    let end = request
        .get("end")
        .and_then(Value::as_u64)
        .and_then(|n| u32::try_from(n).ok())
        .ok_or("INVALID_TEXT_RANGE")?;
    let selected = slice(doc, block, start, end)?;
    let text_len = doc
        .get_plain_text_from_block(block)
        .ok_or("NOT_TEXT")?
        .encode_utf16()
        .count() as u32;
    let (id, text) = text_ref(doc, block, None)?;
    // Capture the next character at the start and previous character at the end:
    // peer inserts before the range don't retarget it; edge inserts stay outside.
    let mut txn = doc.transact_mut();
    let a = text
        .sticky_index(&mut txn, start, Assoc::After)
        // Pinned Yrs has no After position at the end of a nested Y.Text.
        .or_else(|| {
            if start == text_len {
                text.sticky_index(&mut txn, start, Assoc::Before)
            } else {
                None
            }
        })
        .ok_or("INVALID_TEXT_RANGE")?;
    let b = if start == end {
        a.clone()
    } else {
        text.sticky_index(
            &mut txn,
            end,
            if start == end {
                Assoc::After
            } else {
                Assoc::Before
            },
        )
        .ok_or("INVALID_TEXT_RANGE")?
    };
    drop(txn);
    Ok(
        json!({"version":1,"objectId":doc.object_id(),"blockId":block,"textId":id,
        "start":B64.encode(a.encode_v1()),"end":B64.encode(b.encode_v1()),"text":selected}),
    )
}

pub fn resolve(doc: &Document, anchor: &Value) -> Result<(String, String, u32, u32)> {
    if anchor.get("version") != Some(&json!(1)) || field(anchor, "objectId")? != doc.object_id() {
        return Err("INVALID_TEXT_ANCHOR".into());
    }
    let block = field(anchor, "blockId")?;
    let (id, text) = text_ref(doc, block, Some(field(anchor, "textId")?))?;
    let read_index = |key| -> Result<StickyIndex> {
        let s = field(anchor, key)?;
        if s.len() > 1024 {
            return Err("INVALID_TEXT_ANCHOR".into());
        }
        StickyIndex::decode_v1(&decode(s)?).map_err(|_| "INVALID_TEXT_ANCHOR".into())
    };
    let txn = doc.transact();
    let a = read_index("start")?
        .get_offset(&txn)
        .ok_or("ANCHOR_UNRESOLVED")?;
    let b = read_index("end")?
        .get_offset(&txn)
        .ok_or("ANCHOR_UNRESOLVED")?;
    let text_branch: &collab::preclude::branch::Branch = text.as_ref();
    let branch = BranchPtr::from(text_branch);
    if a.branch != branch || b.branch != branch || a.index > b.index {
        return Err("ANCHOR_UNRESOLVED".into());
    }
    Ok((block.into(), id, a.index, b.index))
}

pub fn apply(doc: &mut Document, command: &Value) -> Result<()> {
    let anchor = command.get("anchor").ok_or("INVALID_TEXT_ANCHOR")?;
    let (block, id, start, end) = resolve(doc, anchor)?;
    let href = command.get("href").ok_or("INVALID_LINK")?;
    validate_href(href)?;
    let mut delta = vec![json!({"retain":start})];
    if let Some(label) = command.get("label").and_then(Value::as_str) {
        if label.is_empty() || label.len() > 1024 * 1024 {
            return Err("INVALID_LINK_LABEL".into());
        }
        if anchor.get("text").and_then(Value::as_str)
            != Some(slice(doc, &block, start, end)?.as_str())
        {
            return Err("LINK_TEXT_CHANGED".into());
        }
        // Preserve the existing first character's style when replacing a label.
        let data = doc.get_document_data().map_err(err)?;
        let runs: Vec<Value> = serde_json::from_str(
            data.meta
                .text_map
                .as_ref()
                .and_then(|m| m.get(&id))
                .ok_or("NOT_TEXT")?,
        )
        .map_err(err)?;
        let mut cursor = 0;
        let mut attributes = serde_json::Map::new();
        for run in runs {
            let len = run
                .get("insert")
                .and_then(Value::as_str)
                .unwrap_or("")
                .encode_utf16()
                .count() as u32;
            if cursor <= start {
                attributes = run
                    .get("attributes")
                    .and_then(Value::as_object)
                    .cloned()
                    .unwrap_or_default();
                if start < cursor + len {
                    break;
                }
            }
            cursor += len;
        }
        attributes.insert("href".into(), href.clone());
        if end > start {
            delta.push(json!({"delete":end-start}));
        }
        delta.push(json!({"insert":label,"attributes":attributes}));
    } else {
        if start == end {
            return Err("EMPTY_LINK_RANGE".into());
        }
        delta.push(json!({"retain":end-start,"attributes":{"href":href}}));
    }
    doc.apply_text_delta(&id, serde_json::to_string(&delta).map_err(err)?);
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Session;
    fn document() -> (Session, String) {
        let mut a = Session::open(&uuid::Uuid::new_v4().to_string(), None).unwrap();
        a.operations(&[
            json!({"op":"update_text","path":[0],"delta":[{"insert":"前缀目标😀末尾"}]}),
        ])
        .unwrap();
        let data = a.doc.get_document_data().unwrap();
        let block = data.meta.children_map[&data.blocks[&data.page_id].children][0].clone();
        (a, block)
    }
    #[test]
    fn relative_link_range_survives_peer_prefix_insert_and_origin_undo() {
        let (mut a, block) = document();
        let anchor = capture(&mut a.doc, &json!({"blockId":block,"start":2,"end":6})).unwrap();
        let mut b = Session::open(
            &a.object_id,
            Some(a.doc.encode_collab().unwrap().doc_state.to_vec()),
        )
        .unwrap();
        b.operations(&[json!({"op":"update_text","path":[0],"delta":[{"insert":"协作"}]})])
            .unwrap();
        a.apply_update(&b.doc.encode_collab().unwrap().doc_state)
            .unwrap();
        let (_, _, start, end) = resolve(&a.doc, &anchor).unwrap();
        assert_eq!((start, end), (4, 8));
        assert_eq!(slice(&a.doc, &block, start, end).unwrap(), "目标😀");
        a.operations(&[
            json!({"op":"apply_link","anchor":anchor,"href":"https://example.com/知识"}),
        ])
        .unwrap();
        let data = a.doc.get_document_data().unwrap();
        let text = &data.meta.text_map.as_ref().unwrap()[a
            .doc
            .get_block(&block)
            .unwrap()
            .external_id
            .as_ref()
            .unwrap()];
        assert!(text.contains("https://example.com/知识") && text.contains("目标😀"));
        a.history(false).unwrap();
        assert!(
            a.doc
                .get_plain_text_from_block(&block)
                .unwrap()
                .starts_with("协作")
        );
        assert!(
            !serde_json::to_string(&a.doc.get_document_data().unwrap())
                .unwrap()
                .contains("href")
        );
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
    fn label_precondition_and_invalid_urls_do_not_partially_commit() {
        let (mut a, block) = document();
        let anchor = capture(&mut a.doc, &json!({"blockId":block,"start":2,"end":6})).unwrap();
        a.operations(&[
            json!({"op":"update_text","path":[0],"delta":[{"retain":3},{"insert":"变化"}]}),
        ])
        .unwrap();
        let before = a.snapshot().unwrap();
        assert!(a.operations(&[json!({"op":"apply_link","anchor":anchor,"href":"https://example.com","label":"不要覆盖"})]).unwrap_err().contains("LINK_TEXT_CHANGED"));
        for href in [
            "javascript:alert(1)",
            "data:text/html,x",
            "https://user:password@example.com",
            "file:///private/a",
            "https://example.com\n",
        ] {
            assert!(
                a.operations(&[json!({"op":"apply_link","anchor":anchor,"href":href})])
                    .is_err()
            );
        }
        assert_eq!(before, a.snapshot().unwrap());
        assert!(capture(&mut a.doc, &json!({"blockId":block,"start":7,"end":8})).is_err()); // middle of emoji after insert
    }
    #[test]
    fn forged_cross_text_anchor_and_deleted_target_are_rejected() {
        let (mut a, block) = document();
        a.operations(&[json!({"op":"insert","path":[1],"nodes":[{"id":"other","type":"paragraph","data":{"delta":[{"insert":"另一段"}]}}]})]).unwrap();
        let mut forged =
            capture(&mut a.doc, &json!({"blockId":"other","start":0,"end":1})).unwrap();
        forged["blockId"] = json!(block);
        forged["textId"] = json!(a.doc.get_block(&block).unwrap().external_id.unwrap());
        assert!(resolve(&a.doc, &forged).is_err());
        let anchor = capture(&mut a.doc, &json!({"blockId":block,"start":2,"end":6})).unwrap();
        a.operations(&[json!({"op":"delete","path":[0],"count":1})])
            .unwrap();
        assert!(
            resolve(&a.doc, &anchor)
                .unwrap_err()
                .contains("TARGET_MISSING")
        );
    }
    #[test]
    fn collapsed_link_insert_and_label_edit_keep_surrounding_text_and_style() {
        let (mut a, block) = document();
        a.operations(&[json!({"op":"update_text","path":[0],"delta":[{"retain":8,"attributes":{"bold":true}}]})]).unwrap();
        let anchor = capture(&mut a.doc, &json!({"blockId":block,"start":2,"end":6})).unwrap();
        a.operations(&[json!({"op":"apply_link","anchor":anchor,"href":"mailto:a@example.com","label":"新链接"})]).unwrap();
        assert_eq!(
            a.doc.get_plain_text_from_block(&block).unwrap(),
            "前缀新链接末尾"
        );
        let raw = serde_json::to_string(&a.doc.get_document_data().unwrap()).unwrap();
        assert!(raw.contains("bold") && raw.contains("mailto:"));
        let caret = capture(&mut a.doc, &json!({"blockId":block,"start":7,"end":7})).unwrap();
        a.operations(&[
            json!({"op":"apply_link","anchor":caret,"href":"tel:+8612345","label":"电话"}),
        ])
        .unwrap();
        assert_eq!(
            a.doc.get_plain_text_from_block(&block).unwrap(),
            "前缀新链接末尾电话"
        );
    }
}
