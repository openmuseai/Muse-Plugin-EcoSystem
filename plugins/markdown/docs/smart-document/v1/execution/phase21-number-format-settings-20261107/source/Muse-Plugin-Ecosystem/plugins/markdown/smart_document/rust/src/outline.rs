//! Read-only outline projection over the original AppFlowy Document.
//! Hierarchy follows SiYuan's preceding-lower-heading stack; paths and UI state
//! never enter this projection or the collaborative document.
use collab_document::{
    blocks::{DocumentData, TextDelta},
    document::Document,
};
use serde_json::{Value, json};
use std::collections::HashSet;

pub fn project(doc: &Document, data: &DocumentData) -> Value {
    let mut entries = Vec::new();
    let mut stack: Vec<(u64, String)> = Vec::new();
    let mut pending = vec![data.page_id.clone()];
    let mut seen = HashSet::new();
    let mut warnings = 0;
    while let Some(id) = pending.pop() {
        if !seen.insert(id.clone()) || seen.len() > 10000 {
            return json!({"profile":"muse.document.outline/1","ready":false,"entries":[]});
        }
        let Some(block) = data.blocks.get(&id) else {
            return json!({"profile":"muse.document.outline/1","ready":false,"entries":[]});
        };
        // Closed content scopes (quotes, tables, embeds, unknown extensions)
        // cannot leak their internal headings into this document's navigation.
        if !matches!(
            block.ty.as_str(),
            "page" | "paragraph" | "heading" | "bulleted_list" | "numbered_list" | "todo_list"
        ) {
            continue;
        }
        if block.ty == "heading" {
            if let Some(level @ 1..=6) = block.data.get("level").and_then(Value::as_u64) {
                // Reuse the original kernel's text extraction. Legacy inline
                // deltas are decoded with its own TextDelta type, read-only.
                let text = doc.get_plain_text_from_block(&id).or_else(|| {
                    let delta = block.data.get("delta")?.clone();
                    let runs: Vec<TextDelta> = serde_json::from_value(delta).ok()?;
                    Some(
                        runs.into_iter()
                            .filter_map(|run| match run {
                                TextDelta::Inserted(s, _) => Some(s),
                                _ => None,
                            })
                            .collect::<String>(),
                    )
                });
                if let Some(text) = text {
                    while stack.last().is_some_and(|(previous, _)| *previous >= level) {
                        stack.pop();
                    }
                    entries.push(json!({"blockId":id,"level":level,"depth":stack.len(),
                        "parentId":stack.last().map(|(_, id)| id),
                        "text":text.chars().take(256).collect::<String>(),
                        "truncated":text.chars().count() > 256}));
                    stack.push((level, id.clone()));
                } else {
                    warnings += 1;
                }
            } else {
                warnings += 1;
            }
        }
        if let Some(children) = data.meta.children_map.get(&block.children) {
            pending.extend(children.iter().rev().cloned());
        }
    }
    json!({"profile":"muse.document.outline/1","ready":true,"entries":entries,"warnings":warnings})
}

#[cfg(test)]
mod tests {
    use crate::*;
    #[test]
    fn outline_projects_original_text_and_siyuan_hierarchy_without_writes() {
        let mut s = Session::open(&Uuid::new_v4().to_string(), None).unwrap();
        s.operations(&[json!({"op":"insert","path":[1],"nodes":[
            {"id":"h1","type":"heading","data":{"level":1,"delta":[{"insert":"一😀","attributes":{"bold":true}}]}},
            {"id":"h3","type":"heading","data":{"level":3,"delta":[]}},
            {"id":"quote","type":"quote","children":[{"id":"quoted","type":"heading","data":{"level":2,"delta":[{"insert":"隔离"}]}}]},
            {"id":"h2","type":"heading","data":{"level":2,"delta":[{"insert":"二"}]}},
            {"id":"last","type":"heading","data":{"level":1,"delta":[{"insert":"三"}]}}
        ]})]).unwrap();
        let before = s.doc.encode_collab().unwrap().doc_state;
        let snap = s.snapshot().unwrap();
        let entries = snap["outline"]["entries"].as_array().unwrap();
        assert_eq!(entries.len(), 4);
        assert_eq!(entries[0]["text"], "一😀");
        assert_eq!(entries[1]["text"], "");
        assert_eq!(entries[1]["depth"], 1);
        assert_eq!(entries[2]["parentId"], entries[0]["blockId"]);
        assert_eq!(entries[3]["depth"], 0);
        assert_eq!(before, s.doc.encode_collab().unwrap().doc_state);
    }
    #[test]
    fn outline_tracks_peer_rename_delete_origin_undo_and_reopen() {
        let mut a = Session::open(&Uuid::new_v4().to_string(), None).unwrap();
        a.operations(&[json!({"op":"insert","path":[1],"nodes":[
            {"id":"h","type":"heading","data":{"level":2,"delta":[{"insert":"原题"}]}}
        ]})])
        .unwrap();
        let mut b = Session::open(
            &a.object_id,
            Some(a.doc.encode_collab().unwrap().doc_state.to_vec()),
        )
        .unwrap();
        b.operations(&[
            json!({"op":"update_text","path":[1],"delta":[{"retain":2},{"insert":"😀"}]}),
        ])
        .unwrap();
        a.operations(&[
            json!({"op":"insert","path":[0],"nodes":[{"id":"prefix","type":"paragraph"}]}),
        ])
        .unwrap();
        let ua = a.doc.encode_collab().unwrap().doc_state.to_vec();
        let ub = b.doc.encode_collab().unwrap().doc_state.to_vec();
        a.apply_update(&ub).unwrap();
        b.apply_update(&ua).unwrap();
        assert_eq!(
            a.snapshot().unwrap()["outline"],
            b.snapshot().unwrap()["outline"]
        );
        assert_eq!(
            a.snapshot().unwrap()["outline"]["entries"][0]["blockId"],
            "h"
        );
        assert_eq!(
            a.snapshot().unwrap()["outline"]["entries"][0]["text"],
            "原题😀"
        );
        a.operations(&[json!({"op":"delete","path":[2]})]).unwrap();
        assert!(
            a.snapshot().unwrap()["outline"]["entries"]
                .as_array()
                .unwrap()
                .is_empty()
        );
        a.history(false).unwrap();
        assert_eq!(
            a.snapshot().unwrap()["outline"]["entries"][0]["text"],
            "原题😀"
        );
        let reopened = Session::open(
            &a.object_id,
            Some(a.doc.encode_collab().unwrap().doc_state.to_vec()),
        )
        .unwrap();
        assert_eq!(
            a.snapshot().unwrap()["outline"],
            reopened.snapshot().unwrap()["outline"]
        );
    }
    #[test]
    fn outline_preserves_unknown_levels_and_caps_only_display_text() {
        let mut s = Session::open(&Uuid::new_v4().to_string(), None).unwrap();
        let text = "😀".repeat(300);
        s.operations(&[json!({"op":"insert","path":[1],"nodes":[
            {"id":"bad","type":"heading","data":{"level":99,"delta":[{"insert":"保持原样"}]}},
            {"id":"long","type":"heading","data":{"level":6,"delta":[{"insert":text}]}}
        ]})])
        .unwrap();
        let snap = s.snapshot().unwrap();
        assert_eq!(snap["outline"]["warnings"], 1);
        assert_eq!(
            snap["outline"]["entries"][0]["text"]
                .as_str()
                .unwrap()
                .chars()
                .count(),
            256
        );
        assert_eq!(snap["outline"]["entries"][0]["truncated"], true);
        assert_eq!(s.doc.get_plain_text_from_block("long").unwrap(), text);
        assert_eq!(s.doc.get_block("bad").unwrap().data["level"], 99);
    }

    #[test]
    fn legacy_inline_delta_is_read_with_original_type_without_migration() {
        let id = Uuid::new_v4().to_string();
        let mut data = default_document_data(&id);
        let root = data.blocks[&data.page_id].children.clone();
        data.meta
            .children_map
            .get_mut(&root)
            .unwrap()
            .push("legacy".into());
        data.blocks.insert(
            "legacy".into(),
            Block {
                id: "legacy".into(),
                ty: "heading".into(),
                parent: data.page_id.clone(),
                children: "legacy-children".into(),
                external_id: None,
                external_type: None,
                data: serde_json::from_value(
                    json!({"level":2,"delta":[{"insert":"旧标题😀","attributes":{"bold":true}}]}),
                )
                .unwrap(),
            },
        );
        let doc = Document::create(&id, data, default_client_id()).unwrap();
        let before = doc.encode_collab().unwrap().doc_state;
        let outline = super::project(&doc, &doc.get_document_data().unwrap());
        assert_eq!(outline["entries"][0]["text"], "旧标题😀");
        assert_eq!(before, doc.encode_collab().unwrap().doc_state);
    }
    #[test]
    fn closed_extension_and_table_scopes_never_export_internal_headings() {
        let mut s = Session::open(&Uuid::new_v4().to_string(), None).unwrap();
        s.operations(&[json!({"op":"insert","path":[1],"nodes":[
            {"id":"scope","type":"quote","children":[{"id":"hidden","type":"heading","data":{"level":1,"delta":[{"insert":"内部"}]}}]}
        ]})]).unwrap();
        for ty in [
            "quote",
            "table",
            "table/cell",
            "grid",
            "board",
            "calendar",
            "callout",
            "code",
            "unknown/extension",
        ] {
            let mut data = s.doc.get_document_data().unwrap();
            data.blocks.get_mut("scope").unwrap().ty = ty.into();
            let outline = super::project(&s.doc, &data);
            assert_eq!(outline["ready"], true);
            assert!(outline["entries"].as_array().unwrap().is_empty(), "{ty}");
        }
    }
    #[test]
    fn delete_restored_heading_after_reopen_converges_to_remote_and_checkpoint() {
        let mut seed = Session::open(&Uuid::new_v4().to_string(), None).unwrap();
        seed.operations(&[json!({"op":"insert","path":[1],"nodes":[{"id":"h","type":"heading","data":{"level":3,"delta":[{"insert":"原题"}]}}]})]).unwrap();
        seed.operations(&[json!({"op":"delete","path":[1]})])
            .unwrap();
        seed.history(false).unwrap();
        seed.operations(&[json!({"op":"update_text","path":[1],"delta":[{"insert":"重连 "}]})])
            .unwrap();
        let bytes = seed.doc.encode_collab().unwrap().doc_state.to_vec();
        let mut a = Session::open(&seed.object_id, Some(bytes.clone())).unwrap();
        let mut b = Session::open(&seed.object_id, Some(bytes)).unwrap();
        b.operations(&[json!({"op":"update_text","path":[1],"delta":[{"insert":"Web "}]})])
            .unwrap();
        a.apply_update(&b.doc.encode_collab().unwrap().doc_state)
            .unwrap();
        assert_eq!(
            a.snapshot().unwrap()["outline"]["entries"][0]["text"],
            "Web 重连 原题"
        );
        b.operations(&[json!({"op":"delete","path":[1]})]).unwrap();
        let encoded = b.doc.encode_collab().unwrap().doc_state.to_vec();
        assert!(
            b.snapshot().unwrap()["outline"]["entries"]
                .as_array()
                .unwrap()
                .is_empty()
        );
        a.apply_update(&encoded).unwrap();
        assert_eq!(
            a.snapshot().unwrap()["outline"],
            b.snapshot().unwrap()["outline"]
        );
        let reopened = Session::open(&seed.object_id, Some(encoded)).unwrap();
        assert_eq!(
            reopened.snapshot().unwrap()["outline"],
            b.snapshot().unwrap()["outline"]
        );
    }

    #[test]
    fn captured_original_restored_heading_delete_survives_encoding() {
        let input: Value = serde_json::from_str(include_str!(
            "../fixtures/restored-heading-before-delete.json"
        ))
        .unwrap();
        let mut s = Session::open(
            input["objectId"].as_str().unwrap(),
            Some(B64.decode(input["docState"].as_str().unwrap()).unwrap()),
        )
        .unwrap();
        assert_eq!(s.snapshot().unwrap()["outline"], input["outline"]);
        let data = s.doc.get_document_data().unwrap();
        let root = &data.blocks[&data.page_id];
        let index = data.meta.children_map[&root.children]
            .iter()
            .position(|id| id == "zV7prR")
            .unwrap();
        s.operations(&[json!({"op":"delete","path":[index]})])
            .unwrap();
        let expected = s.snapshot().unwrap()["outline"].clone();
        assert_eq!(expected["entries"].as_array().unwrap().len(), 2);
        let reopened = Session::open(
            &s.object_id,
            Some(s.doc.encode_collab().unwrap().doc_state.to_vec()),
        )
        .unwrap();
        assert_eq!(expected, reopened.snapshot().unwrap()["outline"]);
    }
}
