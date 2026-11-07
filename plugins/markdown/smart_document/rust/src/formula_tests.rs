use crate::{Session, formulas};
use serde_json::json;
#[test]
fn original_formula_block_has_no_parallel_text_and_stale_drafts_are_atomic() {
    let mut s = Session::open(&uuid::Uuid::new_v4().to_string(), None).unwrap();
    let before = s.doc.encode_collab().unwrap();
    assert_eq!(
        s.operations(&[json!({"op":"insert_formula","blockId":"bad","formula":"a".repeat(8193)})])
            .unwrap_err(),
        "FORMULA_INPUT_LIMIT"
    );
    assert_eq!(s.doc.encode_collab().unwrap(), before);
    s.operations(&[json!({"op":"insert_formula","blockId":"eq","formula":r"\frac{a}{b}"})])
        .unwrap();
    let block = s.doc.get_block("eq").unwrap();
    assert!(block.external_id.is_none() && block.external_type.is_none());
    assert_eq!(block.ty, "math_equation");
    let stale = formulas::state(&s.doc, "eq").unwrap();
    let mut attrs = block.data;
    attrs.insert("foreignMetadata".into(), json!({"keep":true}));
    s.doc.update_block("eq", attrs).unwrap();
    s.operations(&[json!({"op":"update_formula","blockId":"eq","formula":r"\sum_{i=1}^{n}i","expectedHash":stale["hash"]})]).unwrap();
    assert_eq!(
        s.doc.get_block("eq").unwrap().data["foreignMetadata"],
        json!({"keep":true})
    );
    let before = s.doc.encode_collab().unwrap();
    assert_eq!(s.operations(&[json!({"op":"update_formula","blockId":"eq","formula":"old draft","expectedHash":stale["hash"]})]).unwrap_err(),"FORMULA_CHANGED");
    assert_eq!(s.doc.encode_collab().unwrap(), before);
    assert_eq!(
        s.operations(&[json!({"op":"delete_formula","blockId":"eq","expectedHash":stale["hash"]})])
            .unwrap_err(),
        "FORMULA_CHANGED"
    );
    let current = formulas::state(&s.doc, "eq").unwrap();
    s.operations(&[json!({"op":"delete_formula","blockId":"eq","expectedHash":current["hash"]})])
        .unwrap();
    assert!(s.doc.get_block("eq").is_none());
    s.history(false).unwrap();
    assert_eq!(formulas::state(&s.doc, "eq").unwrap(), current);
}
#[test]
fn formula_update_and_peer_prose_merge_and_author_undo_keeps_peer_text() {
    let mut a = Session::open(&uuid::Uuid::new_v4().to_string(), None).unwrap();
    a.operations(&[json!({"op":"insert_formula","blockId":"eq","formula":"x^2"})])
        .unwrap();
    let mut b = Session::open(
        &a.object_id,
        Some(a.doc.encode_collab().unwrap().doc_state.to_vec()),
    )
    .unwrap();
    let initial = formulas::state(&a.doc, "eq").unwrap();
    a.operations(&[json!({"op":"update_formula","blockId":"eq","formula":r"\int_0^1 x^2 dx","expectedHash":initial["hash"]})]).unwrap();
    b.operations(&[json!({"op":"update_text","path":[0],"delta":[{"insert":"协作者正文😀"}]})])
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
    assert_eq!(formulas::state(&a.doc, "eq").unwrap()["formula"], "x^2");
    assert!(
        a.doc
            .get_document_data()
            .unwrap()
            .meta
            .text_map
            .unwrap()
            .values()
            .any(|v| v.contains("协作者正文😀"))
    );
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
fn stable_formula_anchor_is_resolved_at_commit_and_failed_batch_changes_nothing() {
    let mut s = Session::open(&uuid::Uuid::new_v4().to_string(), None).unwrap();
    let before = s.doc.encode_collab().unwrap();
    assert_eq!(
        s.operations(&[
            json!({"op":"insert_formula","blockId":"one","formula":"a"}),
            json!({"op":"insert_formula","blockId":"two","formula":"b","afterBlockId":"missing"})
        ])
        .unwrap_err(),
        "TARGET_MISSING"
    );
    assert_eq!(s.doc.encode_collab().unwrap(), before);
    s.operations(&[
        json!({"op":"insert_formula","blockId":"one","formula":"\\futureCommand{source}"}),
    ])
    .unwrap();
    s.operations(&[
        json!({"op":"insert_formula","blockId":"two","formula":"b","afterBlockId":"one"}),
    ])
    .unwrap();
    let data = s.doc.get_document_data().unwrap();
    let children = &data.meta.children_map[&data.blocks[&data.page_id].children];
    assert_eq!(&children[children.len() - 2..], &["one", "two"]);
    let before = s.doc.encode_collab().unwrap();
    assert_eq!(
        s.operations(&[json!({"op":"update","path":[1],"attributes":{"formula":"bypass"}})])
            .unwrap_err(),
        "USE_FORMULA_COMMAND"
    );
    assert_eq!(s.doc.encode_collab().unwrap(), before);
}

#[test]
fn foreign_formula_source_survives_current_render_limits_but_parallel_text_is_invalid() {
    let mut s = Session::open(&uuid::Uuid::new_v4().to_string(), None).unwrap();
    s.operations(&[json!({"op":"insert_formula","blockId":"eq","formula":"x"})])
        .unwrap();
    let mut block = s.doc.get_block("eq").unwrap();
    block.data.insert("formula".into(), json!("x".repeat(9000)));
    s.doc.update_block("eq", block.data.clone()).unwrap();
    let restored = Session::open(
        &s.object_id,
        Some(s.doc.encode_collab().unwrap().doc_state.to_vec()),
    )
    .unwrap();
    assert_eq!(
        formulas::state(&restored.doc, "eq").unwrap()["formula"]
            .as_str()
            .unwrap()
            .len(),
        9000
    );
    block.data.insert("delta".into(), json!([]));
    s.doc.update_block("eq", block.data).unwrap();
    assert!(
        Session::open(
            &s.object_id,
            Some(s.doc.encode_collab().unwrap().doc_state.to_vec())
        )
        .is_err()
    );
}
