use crate::{commands::Command, session::Session, tests::send};
use collab_database::{entity::CreateViewParams, views::DatabaseLayout};
use serde_json::{Value, json};

async fn create() -> Session {
    Session::open(&uuid::Uuid::new_v4().to_string(), None, None)
        .await
        .unwrap()
}
async fn add(s: &mut Session, title: &str) -> String {
    let id = uuid::Uuid::new_v4().to_string();
    s.command(
        serde_json::from_value(json!({"op":"addRow","rowId":id,"cells":{"title":title}})).unwrap(),
    )
    .await
    .unwrap();
    id
}
fn linked<'a>(s: &'a Value, id: &str) -> &'a Value {
    s["views"]
        .as_array()
        .unwrap()
        .iter()
        .find(|v| v["id"] == id)
        .unwrap()
}
#[test]
fn original_linked_view_creation_and_concurrent_row_insert_keep_all_members() {
    futures::executor::block_on(async {
        let mut a = create().await;
        add(&mut a, "已有记录").await;
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        let id = uuid::Uuid::new_v4().to_string();
        a.database
            .create_linked_view(CreateViewParams::new(
                a.object_id.clone(),
                id.clone(),
                "另一个视图".into(),
                DatabaseLayout::Grid,
            ))
            .unwrap();
        let row = add(&mut b, "并发新增").await;
        // Both clients mutate before exchanging either branch.
        send(&b, &mut a).await;
        send(&a, &mut b).await;
        assert_eq!(
            linked(&a.snapshot().await.unwrap(), &id)["rows"]
                .as_array()
                .unwrap()
                .len(),
            2
        );
        assert_eq!(
            linked(&a.snapshot().await.unwrap(), &id),
            linked(&b.snapshot().await.unwrap(), &id)
        );
        assert_eq!(
            a.read_row(&id, &row).await.unwrap()["cells"]["title"]["value"],
            "并发新增"
        );
    });
}
#[test]
fn stale_linked_order_cannot_resurrect_a_concurrently_removed_primary_member() {
    use base64::{Engine, engine::general_purpose::STANDARD as B64};
    futures::executor::block_on(async {
        let mut a = create().await;
        let row = add(&mut a, "删除前").await;
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        let id = uuid::Uuid::new_v4().to_string();
        a.database
            .create_linked_view(CreateViewParams::new(
                a.object_id.clone(),
                id.clone(),
                "并发视图".into(),
                DatabaseLayout::Grid,
            ))
            .unwrap();
        b.database.remove_row(&row.clone().into()).await;
        let root = b
            .bundle()
            .await
            .unwrap()
            .objects
            .into_iter()
            .find(|o| o.object_id == b.object_id)
            .unwrap();
        a.merge(&root.object_id, &B64.decode(root.doc_state).unwrap())
            .await
            .unwrap();
        let before = serde_json::to_value(a.bundle().await.unwrap()).unwrap();
        assert!(
            linked(&a.snapshot().await.unwrap(), &id)["rows"]
                .as_array()
                .unwrap()
                .is_empty()
        );
        assert_eq!(
            a.database.get_view(&id).unwrap().row_orders.len(),
            1,
            "raw stale order remains encoded"
        );
        assert!(a.row_ids().is_empty());
        assert!(a.read_row(&id, &row).await.is_err());
        assert!(a.realtime_object(&row).await.is_err());
        assert_eq!(
            serde_json::to_value(a.bundle().await.unwrap()).unwrap(),
            before,
            "read queries must not repair or rewrite shared data"
        );
        assert!(
            a.bundle()
                .await
                .unwrap()
                .objects
                .iter()
                .any(|o| o.object_id == row),
            "retain original cached row bytes without granting access"
        );
    });
}
#[test]
fn linked_view_commands_preserve_peer_rows_and_stale_names_without_redirecting_identity() {
    futures::executor::block_on(async {
        let mut a = create().await;
        let primary = crate::views::primary(&a.database).unwrap().id;
        let default = a.database.get_all_views()[0].id.clone();
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        let id = uuid::Uuid::new_v4().to_string();
        a.command(Command::CreateGridView {
            view_id: id.clone(),
            name: "我的视图".into(),
        })
        .await
        .unwrap();
        let row = add(&mut b, "另一人新增").await;
        send(&b, &mut a).await;
        send(&a, &mut b).await;
        let before = serde_json::to_value(a.bundle().await.unwrap()).unwrap();
        assert!(
            a.command(Command::CreateGridView {
                view_id: id.clone(),
                name: "重复身份".into()
            })
            .await
            .is_err()
        );
        assert!(
            a.command(Command::RenameView {
                view_id: id.clone(),
                name: "过期名称".into(),
                expected_name: "旧名称".into()
            })
            .await
            .is_err()
        );
        assert_eq!(
            serde_json::to_value(a.bundle().await.unwrap()).unwrap(),
            before
        );
        a.command(Command::RenameView {
            view_id: id.clone(),
            name: "我的改名".into(),
            expected_name: "我的视图".into(),
        })
        .await
        .unwrap();
        send(&a, &mut b).await;
        b.command(Command::RenameView {
            view_id: id.clone(),
            name: "远端名称".into(),
            expected_name: "我的改名".into(),
        })
        .await
        .unwrap();
        send(&b, &mut a).await;
        assert_eq!(
            linked(&a.snapshot().await.unwrap(), &id)["name"],
            "远端名称"
        );
        a.history(false).await.unwrap();
        let state = a.snapshot().await.unwrap();
        assert_eq!(linked(&state, &id)["name"], "远端名称");
        assert_eq!(
            a.read_row(&id, &row).await.unwrap()["cells"]["title"]["value"],
            "另一人新增"
        );
        // The skipped obsolete rename does not fall through to creation.
        assert!(a.database.get_view(&id).is_some());
        a.history(false).await.unwrap();
        assert!(a.database.get_view(&id).is_none());
        assert!(a.database.get_view(&primary).is_some());
        assert_eq!(
            a.read_row(&default, &row).await.unwrap()["cells"]["title"]["value"],
            "另一人新增"
        );
        let reopen = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        assert_eq!(
            reopen.snapshot().await.unwrap()["views"],
            a.snapshot().await.unwrap()["views"]
        );
    });
}
#[test]
fn hidden_primary_membership_has_the_same_scope_and_row_validation_as_visible_views() {
    futures::executor::block_on(async {
        let mut a = create().await;
        let id = crate::views::primary(&a.database).unwrap().id;
        a.database.update_database_view(&id, |update| {
            update.set_database_id("wrong-scope");
        });
        assert_eq!(a.validate().await.unwrap_err(), "INVALID_VIEW_REFERENCE");
        let mut b = create().await;
        let id = crate::views::primary(&b.database).unwrap().id;
        b.database.update_database_view(&id, |update| {
            update.insert_row_order(
                &collab_database::views::RowOrder {
                    id: "not-a-row-uuid".into(),
                    height: 60,
                },
                &collab_database::views::OrderObjectPosition::End,
            );
        });
        assert_eq!(b.validate().await.unwrap_err(), "INVALID_ROW_ID");
    });
}
