use super::*;
use crate::{commands::Command, session::Session};
use serde_json::json;
fn run(f: impl std::future::Future<Output = ()>) {
    futures::executor::block_on(f)
}
async fn new() -> Session {
    Session::open(&uuid::Uuid::new_v4().to_string(), None, None)
        .await
        .unwrap()
}
async fn add(s: &mut Session) -> String {
    let id = uuid::Uuid::new_v4().to_string();
    s.command(Command::AddRow {
        row_id: id.clone(),
        cells: std::collections::HashMap::from([
            ("title".into(), json!("初始😀")),
            ("done".into(), json!(false)),
        ]),
    })
    .await
    .unwrap();
    id
}
async fn hash(s: &Session, row: &str, field: &str) -> String {
    let state = s.snapshot().await.unwrap();
    state["views"][0]["rows"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["id"] == row)
        .unwrap()["cells"][field]["hash"]
        .as_str()
        .unwrap()
        .into()
}
async fn set(s: &mut Session, row: &str, field: &str, value: Value) {
    let expected = hash(s, row, field).await;
    s.command(Command::SetCell {
        row_id: row.into(),
        field_id: field.into(),
        value,
        expected_hash: expected,
        expected_field_hash: None,
    })
    .await
    .unwrap();
}
async fn send(source: &Session, target: &mut Session) {
    for object in source.bundle().await.unwrap().objects {
        target
            .merge(&object.object_id, &B64.decode(object.doc_state).unwrap())
            .await
            .unwrap();
    }
}
#[test]
fn first_write_undo_does_not_remove_a_causally_later_peer_value_in_the_same_cell() {
    run(async {
        let mut a = new().await;
        let row = uuid::Uuid::new_v4().to_string();
        a.command(Command::AddRow {
            row_id: row.clone(),
            cells: Default::default(),
        })
        .await
        .unwrap();
        set(&mut a, &row, "title", json!("first local value")).await;
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        set(&mut b, &row, "title", json!("later peer value")).await;
        send(&b, &mut a).await;
        let undone = a.history(false).await.unwrap();
        assert_eq!(
            undone["views"][0]["rows"][0]["cells"]["title"]["value"],
            "later peer value"
        );
        send(&a, &mut b).await;
        assert_eq!(
            a.snapshot().await.unwrap()["views"],
            b.snapshot().await.unwrap()["views"]
        );
    })
}
#[test]
fn upstream_root_rows_types_cell_writers_and_reopen() {
    run(async {
        let mut a = new().await;
        let row = add(&mut a).await;
        let state = a.snapshot().await.unwrap();
        assert_eq!(
            state["views"][0]["rows"][0]["cells"]["title"]["value"],
            "初始😀"
        );
        let root = a.sync_object(&a.object_id).await.unwrap();
        let child = a.sync_object(&row).await.unwrap();
        assert_eq!(root["collabType"], 1);
        assert_eq!(child["collabType"], 4);
        assert_ne!(root["objectId"], child["objectId"]);
        let b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        assert_eq!(
            a.snapshot().await.unwrap()["views"],
            b.snapshot().await.unwrap()["views"]
        );
    })
}
#[test]
fn independent_cells_converge_and_origin_undo_preserves_peer() {
    run(async {
        let mut a = new().await;
        let row = add(&mut a).await;
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        set(&mut a, &row, "title", json!("甲修改😀")).await;
        set(&mut b, &row, "done", json!(true)).await;
        let ab = a.bundle().await.unwrap();
        let bb = b.bundle().await.unwrap();
        for o in bb.objects {
            a.merge(&o.object_id, &B64.decode(o.doc_state).unwrap())
                .await
                .unwrap();
        }
        for o in ab.objects {
            b.merge(&o.object_id, &B64.decode(o.doc_state).unwrap())
                .await
                .unwrap();
        }
        assert_eq!(
            a.snapshot().await.unwrap()["views"],
            b.snapshot().await.unwrap()["views"]
        );
        let undone = a.history(false).await.unwrap();
        assert_eq!(
            undone["views"][0]["rows"][0]["cells"]["title"]["value"],
            "初始😀"
        );
        assert_eq!(
            undone["views"][0]["rows"][0]["cells"]["done"]["value"],
            true
        );
        send(&a, &mut b).await;
        assert_eq!(
            a.snapshot().await.unwrap()["views"],
            b.snapshot().await.unwrap()["views"]
        );
    })
}
#[test]
fn stale_cell_invalid_type_and_missing_rows_cannot_be_overwritten() {
    run(async {
        let mut a = new().await;
        let row = add(&mut a).await;
        let stale = hash(&a, &row, "title").await;
        set(&mut a, &row, "title", json!("更新")).await;
        let before = a.snapshot().await.unwrap();
        let result = a
            .command(Command::SetCell {
                row_id: row.clone(),
                field_id: "title".into(),
                value: json!("旧草稿"),
                expected_hash: stale,
                expected_field_hash: None,
            })
            .await;
        assert_eq!(result.unwrap_err(), "CELL_CHANGED");
        assert_eq!(a.snapshot().await.unwrap(), before);
        let expected = hash(&a, &row, "done").await;
        assert_eq!(
            a.command(Command::SetCell {
                row_id: row.clone(),
                field_id: "done".into(),
                value: json!("wrong"),
                expected_hash: expected,
                expected_field_hash: None,
            })
            .await
            .unwrap_err(),
            "INVALID_CELL_VALUE"
        );
        let mut incomplete = a.bundle().await.unwrap();
        incomplete.objects.retain(|o| o.collab_type == 1);
        let mut b = Session::open(&a.object_id, Some(incomplete), None)
            .await
            .unwrap();
        assert_eq!(
            b.snapshot().await.unwrap()["views"][0]["rows"][0]["loaded"],
            false
        );
        assert_eq!(
            b.command(Command::SetCell {
                row_id: row,
                field_id: "title".into(),
                value: json!("never blank overwrite"),
                expected_hash: "invalid".into(),
                expected_field_hash: None,
            })
            .await
            .unwrap_err(),
            "ROW_STATE_REQUIRED"
        );
    })
}
#[test]
fn foreign_row_state_is_rejected_atomically_and_unknown_fields_are_preserved() {
    run(async {
        let mut a = new().await;
        let mut foreign = new().await;
        let row = add(&mut foreign).await;
        let state = foreign.sync_object(&row).await.unwrap();
        let before = a.snapshot().await.unwrap();
        assert_eq!(
            a.merge(
                &row,
                &B64.decode(state["docState"].as_str().unwrap()).unwrap()
            )
            .await
            .unwrap_err(),
            "ROW_SCOPE_MISMATCH"
        );
        assert_eq!(a.snapshot().await.unwrap(), before);
        a.database.update_field("title", |update| {
            update.set_field_type(999);
        });
        let b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        let state = b.snapshot().await.unwrap();
        assert_eq!(state["views"][0]["columns"][0]["storageType"], 999);
        assert_eq!(state["views"][0]["columns"][0]["editable"], false);
        // Reopening may garbage-collect deleted CRDT payloads. Preserve the
        // live unknown field/config semantics, not a byte-identical encoding.
        assert_eq!(
            a.snapshot().await.unwrap()["views"],
            b.snapshot().await.unwrap()["views"]
        );
    })
}
#[test]
fn root_undo_hides_created_row_without_destroying_independent_row_state() {
    run(async {
        let mut a = new().await;
        let row = add(&mut a).await;
        let undo = a.history(false).await.unwrap();
        assert!(undo["views"][0]["rows"].as_array().unwrap().is_empty());
        assert_eq!(a.sync_object(&row).await.unwrap()["collabType"], 4);
        let redo = a.history(true).await.unwrap();
        assert_eq!(redo["views"][0]["rows"][0]["id"], row);
    })
}

#[test]
fn timeline_walks_root_and_independent_rows_without_replaying_remote_edits() {
    run(async {
        let mut a = new().await;
        let row = add(&mut a).await;
        set(&mut a, &row, "title", json!("编辑一")).await;
        let mut peer = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        set(&mut peer, &row, "done", json!(true)).await;
        send(&peer, &mut a).await;
        assert_eq!(
            a.history(false).await.unwrap()["views"][0]["rows"][0]["cells"]["title"]["value"],
            "初始😀"
        );
        assert!(
            a.history(false).await.unwrap()["views"][0]["rows"]
                .as_array()
                .unwrap()
                .is_empty()
        );
        assert_eq!(
            a.history(true).await.unwrap()["views"][0]["rows"][0]["cells"]["done"]["value"],
            true
        );
        assert_eq!(
            a.history(true).await.unwrap()["views"][0]["rows"][0]["cells"]["title"]["value"],
            "编辑一"
        );
        a.history(false).await.unwrap();
        a.command(Command::RenameField {
            field_id: "title".into(),
            name: "任务".into(),
            expected_name: "标题".into(),
        })
        .await
        .unwrap();
        assert_eq!(a.snapshot().await.unwrap()["canRedo"], false);
        a.history(false).await.unwrap();
        a.history(false).await.unwrap();
        assert!(
            a.snapshot().await.unwrap()["views"][0]["rows"]
                .as_array()
                .unwrap()
                .is_empty()
        );
    })
}

async fn choice_field(s: &mut Session, id: &str, multi: bool) {
    s.command(Command::CreateField {
        id: id.into(),
        name: if multi {
            "标签".into()
        } else {
            "状态".into()
        },
        semantic_type: if multi {
            "multiSelect".into()
        } else {
            "singleSelect".into()
        },
        options: vec![
            crate::choices::Choice {
                id: "option-a".into(),
                name: "待办,A😀".into(),
                color: 0,
            },
            crate::choices::Choice {
                id: "option-b".into(),
                name: "进行中".into(),
                color: 8,
            },
        ],
    })
    .await
    .unwrap();
}
async fn choice_set(s: &mut Session, row: &str, id: &str, value: Value) -> Result<Value> {
    let state = s.snapshot().await?;
    let field = state["views"][0]["columns"]
        .as_array()
        .unwrap()
        .iter()
        .find(|f| f["id"] == id)
        .unwrap();
    s.command(Command::SetCell {
        row_id: row.into(),
        field_id: id.into(),
        value,
        expected_hash: hash(s, row, id).await,
        expected_field_hash: Some(field["fieldHash"].as_str().unwrap().into()),
    })
    .await
}
#[test]
fn original_select_id_codecs_preserve_comma_names_colors_clear_and_reopen() {
    run(async {
        let mut s = new().await;
        choice_field(&mut s, "state", false).await;
        choice_field(&mut s, "tags", true).await;
        let row = add(&mut s).await;
        choice_set(&mut s, &row, "state", json!(["option-a"]))
            .await
            .unwrap();
        choice_set(&mut s, &row, "tags", json!(["option-b", "option-a"]))
            .await
            .unwrap();
        let state = s.snapshot().await.unwrap();
        let cells = &state["views"][0]["rows"][0]["cells"];
        assert_eq!(cells["state"]["value"], "待办,A😀");
        assert_eq!(cells["state"]["selectedOptionIds"], json!(["option-a"]));
        assert_eq!(cells["tags"]["value"], json!(["进行中", "待办,A😀"]));
        assert_eq!(cells["tags"]["raw"]["data"], "option-b,option-a");
        let reopened = Session::open(&s.object_id, Some(s.bundle().await.unwrap()), None)
            .await
            .unwrap();
        assert_eq!(state["views"], reopened.snapshot().await.unwrap()["views"]);
        choice_set(&mut s, &row, "state", json!([])).await.unwrap();
        assert_eq!(
            s.snapshot().await.unwrap()["views"][0]["rows"][0]["cells"]["state"]["selectedOptionIds"],
            json!([])
        );
    })
}
#[test]
fn select_invalid_or_stale_inputs_reject_without_mutation_and_unknown_config_is_preserved() {
    run(async {
        let mut s = new().await;
        choice_field(&mut s, "state", false).await;
        let row = add(&mut s).await;
        for value in [
            json!(["option-a", "option-b"]),
            json!(["option-a", "option-a"]),
            json!(["missing"]),
            json!("待办,A😀"),
        ] {
            let before = s.snapshot().await.unwrap();
            assert_eq!(
                choice_set(&mut s, &row, "state", value).await.unwrap_err(),
                "INVALID_SELECTION"
            );
            assert_eq!(s.snapshot().await.unwrap(), before);
        }
        let state = s.snapshot().await.unwrap();
        let old = state["views"][0]["columns"]
            .as_array()
            .unwrap()
            .iter()
            .find(|f| f["id"] == "state")
            .unwrap()["fieldHash"]
            .as_str()
            .unwrap()
            .to_owned();
        s.command(Command::RenameField {
            field_id: "state".into(),
            name: "新状态".into(),
            expected_name: "状态".into(),
        })
        .await
        .unwrap();
        let before = s.snapshot().await.unwrap();
        let expected = hash(&s, &row, "state").await;
        assert_eq!(
            s.command(Command::SetCell {
                row_id: row.clone(),
                field_id: "state".into(),
                value: json!(["option-a"]),
                expected_hash: expected,
                expected_field_hash: Some(old)
            })
            .await
            .unwrap_err(),
            "FIELD_CHANGED"
        );
        assert_eq!(s.snapshot().await.unwrap(), before);
        s.database.update_field("state", |update| {
            update.set_type_option(
                3,
                Some(std::collections::HashMap::from([(
                    "content".into(),
                    collab::preclude::Any::String("{future-option-schema}".into()),
                )])),
            );
        });
        let reopened = Session::open(&s.object_id, Some(s.bundle().await.unwrap()), None)
            .await
            .unwrap();
        let state = reopened.snapshot().await.unwrap();
        let col = state["views"][0]["columns"]
            .as_array()
            .unwrap()
            .iter()
            .find(|f| f["id"] == "state")
            .unwrap();
        assert_eq!(col["editable"], false);
        assert_eq!(
            col["raw"]["type_options"]["3"]["content"],
            "{future-option-schema}"
        );
    })
}
#[test]
fn original_select_cells_converge_and_original_origin_undo_preserves_peer_cell() {
    run(async {
        let mut a = new().await;
        choice_field(&mut a, "state", false).await;
        choice_field(&mut a, "tags", true).await;
        let row = add(&mut a).await;
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        choice_set(&mut a, &row, "state", json!(["option-a"]))
            .await
            .unwrap();
        choice_set(&mut b, &row, "tags", json!(["option-b"]))
            .await
            .unwrap();
        let ab = a.bundle().await.unwrap();
        let bb = b.bundle().await.unwrap();
        for o in ab.objects {
            b.merge(&o.object_id, &B64.decode(o.doc_state).unwrap())
                .await
                .unwrap();
        }
        for o in bb.objects {
            a.merge(&o.object_id, &B64.decode(o.doc_state).unwrap())
                .await
                .unwrap();
        }
        assert_eq!(
            a.snapshot().await.unwrap()["views"],
            b.snapshot().await.unwrap()["views"]
        );
        let state = a.history(false).await.unwrap();
        assert_eq!(
            state["views"][0]["rows"][0]["cells"]["state"]["selectedOptionIds"],
            json!([])
        );
        assert_eq!(
            state["views"][0]["rows"][0]["cells"]["tags"]["selectedOptionIds"],
            json!(["option-b"])
        );
    })
}
