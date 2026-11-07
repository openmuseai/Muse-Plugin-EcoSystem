use super::*;
fn target() -> Value {
    json!({"protocol":"openmuse.resource-embed/v1","surface":"dataset.grid",
      "reference":{"protocol":"openmuse.resource-reference/v1","identity":{
        "scope":"test","source":"local","workspace":"test","mount":"root","resource":"dataset"}},
      "selector":{"objectId":"143197bf-8e44-4c1c-a084-d28bd58087a7","viewId":"view-1"}})
}
fn insert(target: Value) -> Value {
    json!({"op":"insert","path":[1],"nodes":[{"id":"inline-grid","type":"grid","data":{
      "parent_id":"document","view_id":"view-1","muse_embed":target}}]})
}
#[test]
fn embed_is_original_structural_locator_with_stable_reopen_and_origin_undo() {
    let mut a = Session::open("769c5ff4-0f5a-45da-9644-3e5c549afabc", None).unwrap();
    a.operations(&[insert(target())]).unwrap();
    let block = a.doc.get_block("inline-grid").unwrap();
    assert_eq!(block.ty, "grid");
    assert!(block.external_id.is_none());
    assert_eq!(block.data["muse_embed"], target());
    let state = a.doc.encode_collab().unwrap().doc_state.to_vec();
    let b = Session::open("769c5ff4-0f5a-45da-9644-3e5c549afabc", Some(state)).unwrap();
    assert_eq!(b.doc.get_block("inline-grid").unwrap().data, block.data);
    a.history(false).unwrap();
    assert!(a.doc.get_block("inline-grid").is_none());
    a.history(true).unwrap();
    assert_eq!(a.doc.get_block("inline-grid").unwrap().data, block.data);
}
#[test]
fn embed_rejects_authority_injection_mismatched_view_and_nested_content_atomically() {
    let mut a = Session::open("769c5ff4-0f5a-45da-9644-3e5c549afabc", None).unwrap();
    for mutation in 0..4 {
        let mut t = target();
        match mutation {
            0 => t["reference"]["token"] = json!("must-not-be-portable"),
            1 => t["reference"]["identity"]["resource"] = json!("/private/dataset"),
            2 => t["selector"]["viewId"] = json!("another-view"),
            _ => t["selector"]["rows"] = json!([{"title":"not-a-locator"}]),
        }
        let before = a.snapshot().unwrap()["docState"].clone();
        assert!(a.operations(&[insert(t)]).is_err());
        assert_eq!(a.snapshot().unwrap()["docState"], before);
    }
    let mut op = insert(target());
    op["nodes"][0]["children"] =
        json!([{"id":"not-inline-row","type":"paragraph","data":{"delta":[]}}]);
    assert!(a.operations(&[op]).is_err());
    assert!(a.doc.get_block("inline-grid").is_none());
}
#[test]
fn original_database_locators_are_retained_without_fabricated_resource_mapping() {
    let mut a = Session::open("769c5ff4-0f5a-45da-9644-3e5c549afabc", None).unwrap();
    let mut op = insert(target());
    op["nodes"][0]["data"]
        .as_object_mut()
        .unwrap()
        .remove("muse_embed");
    a.operations(&[op]).unwrap();
    assert!(
        !a.doc
            .get_block("inline-grid")
            .unwrap()
            .data
            .contains_key("muse_embed")
    );
}
