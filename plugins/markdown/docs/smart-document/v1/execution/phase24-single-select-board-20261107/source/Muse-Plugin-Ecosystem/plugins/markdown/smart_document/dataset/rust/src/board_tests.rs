use crate::{session::Session, tests::send};
use serde_json::{Value, json};
async fn command(s: &mut Session, v: Value) -> crate::Result<Value> {
    s.command(serde_json::from_value(v).unwrap()).await
}
async fn setup() -> (Session, String, String) {
    let mut s = Session::open(&uuid::Uuid::new_v4().to_string(), None, None)
        .await
        .unwrap();
    command(&mut s,json!({"op":"createField","id":"status","name":"状态","semanticType":"singleSelect","options":[{"id":"todo","name":"待处理","color":1},{"id":"doing","name":"进行中","color":2},{"id":"done","name":"已完成","color":3}]})).await.unwrap();
    let row = uuid::Uuid::new_v4().to_string();
    command(
        &mut s,
        json!({"op":"addRow","rowId":row,"cells":{"title":"原始记录","status":["todo"]}}),
    )
    .await
    .unwrap();
    let field = s.database.get_field("status").unwrap();
    let view = uuid::Uuid::new_v4().to_string();
    command(&mut s,json!({"op":"createBoardView","viewId":view,"name":"任务看板","fieldId":"status","expectedFieldHash":crate::model::field_hash(&field)})).await.unwrap();
    (s, view, row)
}
fn view<'a>(s: &'a Value, id: &str) -> &'a Value {
    s["views"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["id"] == id)
        .unwrap()
}
fn move_command(s: &Value, id: &str, row: &str, group: &str) -> Value {
    let v = view(s, id);
    let r = v["rows"]
        .as_array()
        .unwrap()
        .iter()
        .find(|r| r["id"] == row)
        .unwrap();
    json!({"op":"moveBoardCard","viewId":id,"rowId":row,"groupId":group,"expectedBoardHash":v["board"]["hash"].as_str().unwrap_or("unsupported"),"expectedHash":r["cells"]["status"]["hash"]})
}
#[test]
fn board_is_pure_projection_and_moves_the_original_row_with_independent_undo() {
    futures::executor::block_on(async {
        let (mut a, id, row) = setup().await;
        let before = serde_json::to_value(a.bundle().await.unwrap()).unwrap();
        let snapshot = a.snapshot().await.unwrap();
        let board = &view(&snapshot, &id)["board"];
        assert_eq!(board["ready"], true);
        assert_eq!(board["groups"][0]["id"], "status");
        assert_eq!(board["groups"][1]["rowIds"], json!([row]));
        assert_eq!(
            before,
            serde_json::to_value(a.bundle().await.unwrap()).unwrap()
        );
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        let stale = move_command(&snapshot, &id, &row, "done");
        command(&mut a, move_command(&snapshot, &id, &row, "doing"))
            .await
            .unwrap();
        let bs = b.snapshot().await.unwrap();
        let original = &bs["views"][0]["rows"][0];
        command(&mut b,json!({"op":"setCell","rowId":row,"fieldId":"title","value":"协作者改标题","expectedHash":original["cells"]["title"]["hash"]})).await.unwrap();
        send(&b, &mut a).await;
        send(&a, &mut b).await;
        assert_eq!(
            a.snapshot().await.unwrap()["views"],
            b.snapshot().await.unwrap()["views"]
        );
        let stable = serde_json::to_value(a.bundle().await.unwrap()).unwrap();
        assert_eq!(command(&mut a, stale).await.unwrap_err(), "CELL_CHANGED");
        assert_eq!(
            stable,
            serde_json::to_value(a.bundle().await.unwrap()).unwrap()
        );
        a.history(false).await.unwrap();
        let state = a.snapshot().await.unwrap();
        let original = &view(&state, &id)["rows"][0];
        assert_eq!(
            original["cells"]["status"]["selectedOptionIds"],
            json!(["todo"])
        );
        assert_eq!(original["cells"]["title"]["value"], "协作者改标题");
        command(&mut a, move_command(&state, &id, &row, "status"))
            .await
            .unwrap();
        assert_eq!(
            view(&a.snapshot().await.unwrap(), &id)["board"]["groups"][0]["rowIds"],
            json!([row])
        );
        let reopened = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        assert_eq!(
            a.snapshot().await.unwrap()["views"],
            reopened.snapshot().await.unwrap()["views"]
        );
        assert_eq!(
            a.bundle().await.unwrap().objects.len(),
            2,
            "one root and the original row only"
        );
    });
}
#[test]
fn concurrent_board_creation_and_row_insert_keep_shared_membership() {
    futures::executor::block_on(async {
        let (mut a, old_id, _) = setup().await;
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        let id = uuid::Uuid::new_v4().to_string();
        let field = a.database.get_field("status").unwrap();
        command(&mut a,json!({"op":"createBoardView","viewId":id,"name":"第二看板","fieldId":"status","expectedFieldHash":crate::model::field_hash(&field)})).await.unwrap();
        let row = uuid::Uuid::new_v4().to_string();
        command(&mut b,json!({"op":"addRow","viewId":old_id,"rowId":row,"cells":{"title":"并发卡片","status":["done"]}})).await.unwrap();
        send(&a, &mut b).await;
        send(&b, &mut a).await;
        let state = a.snapshot().await.unwrap();
        assert_eq!(view(&state, &id)["rows"].as_array().unwrap().len(), 2);
        assert_eq!(
            view(&state, &id)["board"]["groups"][3]["rowIds"],
            json!([row])
        );
        assert_eq!(state["views"], b.snapshot().await.unwrap()["views"]);
    });
}
#[test]
fn original_group_order_visibility_hide_empty_and_unknown_configuration_are_preserved() {
    futures::executor::block_on(async {
        use collab_database::views::{Group, GroupSetting};
        let (mut a, id, _) = setup().await;
        let mut setting: GroupSetting =
            GroupSetting::try_from(a.database.get_view(&id).unwrap().group_settings[0].clone())
                .unwrap();
        setting.groups = vec![
            Group::new("done".into()),
            Group {
                id: "todo".into(),
                visible: false,
            },
            Group::new("status".into()),
        ];
        setting.content = "{\"hide_empty\":true}".into();
        a.database.insert_group_setting(&id, setting.clone());
        let before = serde_json::to_value(a.bundle().await.unwrap()).unwrap();
        let state = a.snapshot().await.unwrap();
        assert_eq!(view(&state, &id)["board"]["groups"], json!([]));
        assert_eq!(
            before,
            serde_json::to_value(a.bundle().await.unwrap()).unwrap()
        );
        setting.content = "{\"future_mode\":true}".into();
        a.database.insert_group_setting(&id, setting);
        let before = serde_json::to_value(a.bundle().await.unwrap()).unwrap();
        let state = a.snapshot().await.unwrap();
        assert_eq!(view(&state, &id)["board"]["ready"], false);
        assert_eq!(
            command(
                &mut a,
                move_command(
                    &state,
                    &id,
                    state["views"][0]["rows"][0]["id"].as_str().unwrap(),
                    "done"
                )
            )
            .await
            .unwrap_err(),
            "UNSUPPORTED_BOARD_CONFIGURATION"
        );
        assert_eq!(
            before,
            serde_json::to_value(a.bundle().await.unwrap()).unwrap()
        );
    });
}
