use crate::{commands::Command, session::Session, tests::send, view_rules};
use serde_json::{Value, json};
fn run(f: impl std::future::Future<Output = ()>) {
    futures::executor::block_on(f)
}
async fn new() -> Session {
    let mut s = Session::open(&uuid::Uuid::new_v4().to_string(), None, None)
        .await
        .unwrap();
    s.command(Command::CreateField {
        id: "amount".into(),
        name: "金额".into(),
        semantic_type: "number".into(),
        options: vec![],
        timezone: None,
    })
    .await
    .unwrap();
    s
}
async fn add(s: &mut Session, title: &str, amount: Option<&str>) -> String {
    let id = uuid::Uuid::new_v4().to_string();
    let mut cells = std::collections::HashMap::from([("title".into(), json!(title))]);
    if let Some(a) = amount {
        cells.insert("amount".into(), json!(a));
    }
    s.command(Command::AddRow {
        view_id: None,
        row_id: id.clone(),
        cells,
    })
    .await
    .unwrap();
    id
}
async fn view(s: &Session) -> Value {
    s.snapshot().await.unwrap()["views"][0].clone()
}
fn ids(v: &Value) -> Vec<String> {
    v["rows"]
        .as_array()
        .unwrap()
        .iter()
        .map(|r| r["id"].as_str().unwrap().into())
        .collect()
}
async fn configure(s: &mut Session, filters: Value, sorts: Value) -> crate::Result<Value> {
    let v = view(s).await;
    s.command(serde_json::from_value(json!({"op":"configureViewRules","viewId":v["id"],"filters":filters,"sorts":sorts,"expectedRulesHash":v["rulesHash"],"expectedFieldsHash":v["fieldsHash"]})).unwrap()).await
}
fn text(id: &str, op: i64, content: &str) -> Value {
    json!({"id":id,"filter_type":2,"field_id":"title","ty":0,"condition":op,"content":content})
}
fn sort(field: &str, descending: bool) -> Value {
    json!({"id":format!("sort-{field}"),"field_id":field,"condition":if descending{1}else{0}})
}
#[test]
fn original_filter_tree_stable_multi_sort_and_does_not_remove_rows() {
    run(async {
        let mut s = new().await;
        let a = add(&mut s, "Muse A", Some("9007199254740993")).await;
        let b = add(&mut s, "muse B", Some("9007199254740992")).await;
        let c = add(&mut s, "Other", None).await;
        configure(&mut s,json!([{"id":"root","filter_type":1,"children":[text("one",2,"MUSE"),text("two",0,"Other")]}]),json!([sort("amount",false)])).await.unwrap();
        let v = view(&s).await;
        assert_eq!(v["rulesReady"], true);
        assert_eq!(ids(&v), vec![b.clone(), a.clone(), c.clone()]);
        assert_eq!(s.row_ids().len(), 3);
        configure(
            &mut s,
            json!([text("one", 2, "MUSE")]),
            json!([sort("amount", true)]),
        )
        .await
        .unwrap();
        assert_eq!(ids(&view(&s).await), vec![a, b]);
        configure(&mut s, json!([]), json!([sort("amount", true)]))
            .await
            .unwrap();
        assert_eq!(ids(&view(&s).await).last(), Some(&c));
    })
}
#[test]
fn filter_command_is_root_history_and_peer_cell_edit_survives_undo() {
    run(async {
        let mut a = new().await;
        let row = add(&mut a, "visible", Some("1")).await;
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        configure(&mut a, json!([text("f", 0, "hidden")]), json!([]))
            .await
            .unwrap();
        assert!(ids(&view(&a).await).is_empty());
        send(&a, &mut b).await;
        assert!(ids(&view(&b).await).is_empty());
        let row_data = b
            .reader
            .rows
            .get(&collab_database::rows::RowId::from(row.clone()))
            .unwrap()
            .clone();
        let hash = crate::model::hash(row_data.read().await.get_cell("title").as_ref());
        b.command(Command::SetCell {
            row_id: row.clone(),
            field_id: "title".into(),
            value: json!("hidden"),
            expected_hash: hash,
            expected_field_hash: None,
        })
        .await
        .unwrap();
        send(&b, &mut a).await;
        assert_eq!(ids(&view(&a).await), vec![row.clone()]);
        a.history(false).await.unwrap();
        send(&a, &mut b).await;
        assert_eq!(view(&a).await["filters"], json!([]));
        assert_eq!(
            view(&b).await["rows"][0]["cells"]["title"]["value"],
            "hidden"
        );
    })
}
#[test]
fn stale_config_and_changed_field_drafts_reject_without_mutation() {
    run(async {
        let mut s = new().await;
        add(&mut s, "A", Some("1")).await;
        let old = view(&s).await;
        configure(&mut s, json!([text("f", 2, "A")]), json!([]))
            .await
            .unwrap();
        let before = s.bundle().await.unwrap();
        let command = json!({"op":"configureViewRules","viewId":old["id"],"filters":[],"sorts":[],"expectedRulesHash":old["rulesHash"],"expectedFieldsHash":old["fieldsHash"]});
        assert_eq!(
            s.command(serde_json::from_value(command).unwrap())
                .await
                .unwrap_err(),
            "VIEW_RULES_CHANGED"
        );
        assert_eq!(
            serde_json::to_value(s.bundle().await.unwrap()).unwrap(),
            serde_json::to_value(before).unwrap()
        );
        let old = view(&s).await;
        s.command(Command::RenameField {
            field_id: "title".into(),
            name: "Renamed".into(),
            expected_name: "名称".into(),
        })
        .await
        .err();
        // A real schema change, regardless of the default localized field name.
        s.database.update_field("title", |u| {
            u.set_name("New title");
        });
        assert_ne!(old["fieldsHash"], view(&s).await["fieldsHash"]);
        let command = json!({"op":"configureViewRules","viewId":old["id"],"filters":[],"sorts":[],"expectedRulesHash":old["rulesHash"],"expectedFieldsHash":old["fieldsHash"]});
        assert_eq!(
            s.command(serde_json::from_value(command).unwrap())
                .await
                .unwrap_err(),
            "VIEW_RULES_CHANGED"
        );
    })
}
#[test]
fn unknown_rule_is_preserved_in_manual_read_only_projection_and_cannot_be_overwritten() {
    run(async {
        let mut s = new().await;
        let row = add(&mut s, "A", None).await;
        let id = view(&s).await["id"].as_str().unwrap().to_string();
        let unknown = json!([{"id":"future","field_id":"title","filter_type":2,"ty":0,"condition":99,"content":"A","future":true}]);
        s.database.update_database_view(&id, |u| {
            u.set_filters(view_rules::maps(unknown.clone()).unwrap());
        });
        let v = view(&s).await;
        assert_eq!(v["rulesReady"], false);
        assert_eq!(v["filters"], unknown);
        assert_eq!(ids(&v), vec![row]);
        assert!(configure(&mut s, json!([]), json!([])).await.is_err());
        assert_eq!(view(&s).await["filters"], unknown);
    })
}
#[test]
fn missing_rows_are_not_empty_filter_results_and_reopen_retains_original_rules() {
    run(async {
        let mut s = new().await;
        let row = add(&mut s, "A", Some("1")).await;
        configure(
            &mut s,
            json!([text("f", 0, "not-A")]),
            json!([sort("amount", false)]),
        )
        .await
        .unwrap();
        let mut bundle = s.bundle().await.unwrap();
        bundle.objects.retain(|o| o.collab_type == 1);
        let reopened = Session::open(&s.object_id, Some(bundle), None)
            .await
            .unwrap();
        let v = view(&reopened).await;
        assert_eq!(ids(&v), vec![row]);
        assert_eq!(v["rows"][0]["loaded"], false);
        assert_eq!(v["matchedRows"], 0);
    })
}
#[test]
fn invalid_nodes_numbers_and_duplicate_keys_fail_without_dropping_unknowns() {
    run(async {
        let mut s = new().await;
        let fields = s.database.get_fields(None);
        for filters in [
            json!([{"id":"f","field_id":"amount","ty":1,"condition":0,"content":"abc"}]),
            json!([text("dup", 0, "A"), text("dup", 0, "B")]),
            json!([{"id":"g","filter_type":99,"children":[]}]),
        ] {
            assert!(view_rules::Rules::parse(&filters, &json!([]), &fields).is_err());
        }
        assert!(
            configure(
                &mut s,
                json!([]),
                json!([sort("title", false), sort("title", true)])
            )
            .await
            .is_err()
        );
        let mut deep = text("leaf", 0, "A");
        for n in 0..10 {
            deep = json!({"id":format!("g{n}"),"filter_type":0,"children":[deep]});
        }
        assert!(view_rules::Rules::parse(&json!([deep]), &json!([]), &fields).is_err());
    })
}

#[test]
fn original_option_ids_declared_rank_checkbox_and_explicit_date_instants_sort() {
    run(async {
        let mut s = new().await;
        for (id, ty) in [("state", "singleSelect"), ("date", "date")] {
            s.command(Command::CreateField {
                id: id.into(),
                name: id.into(),
                semantic_type: ty.into(),
                timezone: if ty == "date" {
                    Some("Asia/Shanghai".into())
                } else {
                    None
                },
                options: if ty == "singleSelect" {
                    vec![
                        crate::choices::Choice {
                            id: "first".into(),
                            name: "Zulu".into(),
                            color: 0,
                        },
                        crate::choices::Choice {
                            id: "second".into(),
                            name: "Alpha".into(),
                            color: 0,
                        },
                    ]
                } else {
                    vec![]
                },
            })
            .await
            .unwrap();
        }
        let mut rows = vec![];
        for (name, option, done, start) in [
            ("A", "second", true, "2026-11-07T09:00:00+08:00"),
            ("B", "first", false, "2026-11-07T08:00:00+08:00"),
        ] {
            let id = uuid::Uuid::new_v4().to_string();
            s.command(Command::AddRow {
                view_id: None,
                row_id: id.clone(),
                cells: std::collections::HashMap::from([
                    ("title".into(), json!(name)),
                    ("state".into(), json!([option])),
                    ("done".into(), json!(done)),
                    (
                        "date".into(),
                        json!({"start":start,"end":null,"includeTime":true,"isRange":false}),
                    ),
                ]),
            })
            .await
            .unwrap();
            rows.push(id);
        }
        configure(&mut s, json!([]), json!([sort("state", false)]))
            .await
            .unwrap();
        assert_eq!(ids(&view(&s).await), vec![rows[1].clone(), rows[0].clone()]);
        configure(&mut s, json!([]), json!([sort("date", true)]))
            .await
            .unwrap();
        assert_eq!(ids(&view(&s).await), rows);
        configure(&mut s,json!([{"id":"f","filter_type":2,"field_id":"state","ty":3,"condition":0,"content":"first"}]),json!([])).await.unwrap();
        assert_eq!(ids(&view(&s).await), vec![rows[1].clone()]);
        configure(
            &mut s,
            json!([{"id":"f","filter_type":2,"field_id":"done","ty":5,"condition":0,"content":""}]),
            json!([]),
        )
        .await
        .unwrap();
        assert_eq!(ids(&view(&s).await), vec![rows[0].clone()]);
    })
}
#[test]
fn hidden_rows_remain_authoritative_dependencies_and_reproject_on_original_row_merge() {
    run(async {
        let mut a = new().await;
        let row = add(&mut a, "before", None).await;
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        configure(&mut a, json!([text("f", 0, "after")]), json!([]))
            .await
            .unwrap();
        let v = view(&a).await;
        assert!(ids(&v).is_empty());
        assert_eq!(v["rowObjects"][0]["id"], row);
        assert_eq!(v["rowObjects"][0]["loaded"], true);
        let before = view(&b).await;
        let hash = before["rows"][0]["cells"]["title"]["hash"]
            .as_str()
            .unwrap();
        b.command(Command::SetCell {
            row_id: row.clone(),
            field_id: "title".into(),
            value: json!("after"),
            expected_hash: hash.into(),
            expected_field_hash: None,
        })
        .await
        .unwrap();
        let object = b.sync_object(&row).await.unwrap();
        a.merge(
            &row,
            &base64::Engine::decode(
                &base64::engine::general_purpose::STANDARD,
                object["docState"].as_str().unwrap(),
            )
            .unwrap(),
        )
        .await
        .unwrap();
        assert_eq!(ids(&view(&a).await), vec![row]);
    })
}
#[test]
fn empty_group_has_original_tristate_semantics_inside_and_or() {
    run(async {
        let mut s = new().await;
        let row = add(&mut s, "A", None).await;
        let empty = json!({"id":"empty","filter_type":1,"children":[]});
        configure(
            &mut s,
            json!([{"id":"outer","filter_type":1,"children":[empty.clone(),text("leaf",0,"B")]}]),
            json!([]),
        )
        .await
        .unwrap();
        assert!(ids(&view(&s).await).is_empty());
        configure(
            &mut s,
            json!([{"id":"outer","filter_type":0,"children":[empty,text("leaf",0,"A")]}]),
            json!([]),
        )
        .await
        .unwrap();
        assert_eq!(ids(&view(&s).await), vec![row]);
    })
}
#[test]
fn stable_priority_sort_uses_secondary_key_and_manual_order_for_equal_keys() {
    run(async {
        let mut s = new().await;
        let b = add(&mut s, "B", Some("1")).await;
        let a = add(&mut s, "A", Some("1")).await;
        let a2 = add(&mut s, "A", Some("1")).await;
        let empty = add(&mut s, "Z", None).await;
        configure(
            &mut s,
            json!([]),
            json!([sort("amount", false), sort("title", false)]),
        )
        .await
        .unwrap();
        assert_eq!(
            ids(&view(&s).await),
            vec![a.clone(), a2.clone(), b.clone(), empty.clone()]
        );
        configure(
            &mut s,
            json!([]),
            json!([sort("amount", true), sort("title", true)]),
        )
        .await
        .unwrap();
        assert_eq!(ids(&view(&s).await), vec![b, a, a2, empty]);
    })
}
#[test]
fn malformed_cell_types_do_not_silently_filter_out_or_sort_as_empty() {
    run(async {
        let mut s = new().await;
        let id = add(&mut s, "A", None).await;
        configure(&mut s, json!([text("f", 0, "A")]), json!([]))
            .await
            .unwrap();
        let row = s
            .reader
            .rows
            .get(&collab_database::rows::RowId::from(id.clone()))
            .unwrap()
            .clone();
        row.write().await.update(|u| {
            u.update_cells(|c| {
                c.insert_cell(
                    "title",
                    std::collections::HashMap::from([
                        ("field_type".into(), collab::preclude::Any::BigInt(0)),
                        ("data".into(), collab::preclude::Any::Bool(true)),
                    ]),
                );
            });
        });
        let v = view(&s).await;
        assert_eq!(v["rulesReady"], false);
        assert_eq!(ids(&v), vec![id]);
        assert_eq!(v["rows"][0]["cells"]["title"]["raw"]["data"], true);
    })
}

#[test]
fn simultaneous_existing_leaf_edits_converge_without_duplicate_filter_nodes() {
    run(async {
        let mut a = new().await;
        add(&mut a, "A", None).await;
        add(&mut a, "B", None).await;
        configure(&mut a, json!([text("shared", 2, "")]), json!([]))
            .await
            .unwrap();
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        configure(&mut a, json!([text("shared", 2, "A")]), json!([]))
            .await
            .unwrap();
        configure(&mut b, json!([text("shared", 2, "B")]), json!([]))
            .await
            .unwrap();
        send(&a, &mut b).await;
        send(&b, &mut a).await;
        let av = view(&a).await;
        let bv = view(&b).await;
        assert_eq!(av, bv);
        assert_eq!(
            av["rulesReady"], true,
            "shared original rule must remain editable after concurrent writes"
        );
        assert_eq!(av["filters"].as_array().unwrap().len(), 1);
    })
}
#[test]
fn simultaneous_filter_and_sort_edits_preserve_independent_shared_view_intents() {
    run(async {
        let mut a = new().await;
        add(&mut a, "A", None).await;
        add(&mut a, "B", None).await;
        configure(&mut a, json!([text("shared", 2, "")]), json!([]))
            .await
            .unwrap();
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        configure(&mut a, json!([text("shared", 2, "A")]), json!([]))
            .await
            .unwrap();
        configure(
            &mut b,
            json!([text("shared", 2, "")]),
            json!([sort("title", true)]),
        )
        .await
        .unwrap();
        send(&a, &mut b).await;
        send(&b, &mut a).await;
        let av = view(&a).await;
        assert_eq!(av, view(&b).await);
        assert_eq!(av["rulesReady"], true);
        assert_eq!(av["filters"][0]["content"], "A");
        assert_eq!(av["sorts"][0]["condition"], 1);
        assert_eq!(av["rows"].as_array().unwrap().len(), 1);
    })
}
#[test]
fn concurrent_rule_condition_content_pairs_remain_coherent_under_both_client_orders() {
    run(async {
        for (aid, bid) in [(101, 202), (202, 101)] {
            let mut base = new().await;
            add(&mut base, "A", Some("1")).await;
            configure(&mut base, json!([text("shared", 2, "base")]), json!([]))
                .await
                .unwrap();
            let bundle = base.bundle().await.unwrap();
            let mut a = Session::open(&base.object_id, Some(bundle.clone()), Some(aid))
                .await
                .unwrap();
            let mut b = Session::open(&base.object_id, Some(bundle), Some(bid))
                .await
                .unwrap();
            configure(&mut a, json!([text("shared", 0, "equal-A")]), json!([]))
                .await
                .unwrap();
            configure(&mut b, json!([text("shared", 2, "contains-B")]), json!([]))
                .await
                .unwrap();
            send(&b, &mut a).await;
            send(&a, &mut b).await;
            send(&b, &mut a).await;
            let av = view(&a).await;
            assert_eq!(av, view(&b).await);
            assert_eq!(av["rulesReady"], true);
            let f = &av["filters"][0];
            assert!(
                (f["condition"] == 0 && f["content"] == "equal-A")
                    || (f["condition"] == 2 && f["content"] == "contains-B")
            );
        }
    })
}
#[test]
fn concurrent_independent_additions_to_empty_original_view_arrays_are_preserved() {
    run(async {
        let mut a = new().await;
        add(&mut a, "A", None).await;
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        configure(&mut a, json!([text("new-a", 2, "A")]), json!([]))
            .await
            .unwrap();
        configure(&mut b, json!([]), json!([sort("title", true)]))
            .await
            .unwrap();
        send(&b, &mut a).await;
        send(&a, &mut b).await;
        let av = view(&a).await;
        assert_eq!(av, view(&b).await);
        assert_eq!(av["filters"][0]["id"], "new-a");
        assert_eq!(av["sorts"][0]["field_id"], "title");
        assert_eq!(av["rulesReady"], true);
    })
}
#[test]
fn concurrent_new_distinct_filters_and_remove_versus_existing_edit_have_valid_original_semantics() {
    run(async {
        let mut a = new().await;
        add(&mut a, "A", None).await;
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        configure(&mut a, json!([text("new-a", 2, "A")]), json!([]))
            .await
            .unwrap();
        configure(&mut b, json!([text("new-b", 2, "B")]), json!([]))
            .await
            .unwrap();
        send(&b, &mut a).await;
        send(&a, &mut b).await;
        let av = view(&a).await;
        assert_eq!(av, view(&b).await);
        assert_eq!(av["filters"].as_array().unwrap().len(), 2);
        assert_eq!(av["rulesReady"], true);
        let mut c = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        configure(&mut a, json!([]), json!([])).await.unwrap();
        configure(
            &mut c,
            json!([text("new-a", 2, "new peer A"), text("new-b", 2, "B")]),
            json!([]),
        )
        .await
        .unwrap();
        send(&c, &mut a).await;
        send(&a, &mut c).await;
        assert_eq!(view(&a).await, view(&c).await);
        assert_eq!(view(&a).await["filters"], json!([]));
        assert_eq!(a.row_ids().len(), 1);
    })
}
#[test]
fn concurrent_original_sort_moves_converge_without_duplicate_nodes() {
    run(async {
        let mut a = new().await;
        add(&mut a, "A", Some("1")).await;
        configure(
            &mut a,
            json!([]),
            json!([
                sort("title", false),
                sort("amount", false),
                sort("url", false)
            ]),
        )
        .await
        .unwrap();
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        configure(
            &mut a,
            json!([]),
            json!([
                sort("amount", false),
                sort("title", false),
                sort("url", false)
            ]),
        )
        .await
        .unwrap();
        configure(
            &mut b,
            json!([]),
            json!([
                sort("title", false),
                sort("url", false),
                sort("amount", false)
            ]),
        )
        .await
        .unwrap();
        send(&a, &mut b).await;
        send(&b, &mut a).await;
        let av = view(&a).await;
        assert_eq!(av, view(&b).await);
        assert_eq!(av["rulesReady"], true);
        assert_eq!(av["sorts"].as_array().unwrap().len(), 3);
    })
}
#[test]
fn view_undo_after_causally_later_peer_rule_edit_does_not_fall_through_to_prior_root_command() {
    run(async {
        let mut a = new().await;
        let row = add(&mut a, "A", None).await;
        configure(&mut a, json!([text("shared", 2, "base")]), json!([]))
            .await
            .unwrap();
        configure(&mut a, json!([text("shared", 2, "local")]), json!([]))
            .await
            .unwrap();
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        configure(&mut b, json!([text("shared", 2, "peer")]), json!([]))
            .await
            .unwrap();
        send(&b, &mut a).await;
        a.history(false).await.unwrap();
        let av = view(&a).await;
        assert_eq!(
            av["filters"].as_array().unwrap().len(),
            1,
            "undoing an overwritten edit must not delete the earlier filter creation"
        );
        assert_eq!(av["filters"][0]["content"], "peer");
        assert!(a.row_ids().contains(&row));
    })
}
