use crate::{choices, commands::Command, model, session::Session, view_rules::Rules};
use collab_database::{
    entity::FieldType,
    fields::{
        Field,
        number_type_option::{NumberFormat, NumberTypeOption},
    },
};
use serde_json::{Value, json};
fn leaf(id: &str, field: &str, ty: i64, condition: i64, content: &str) -> Value {
    json!({"id":id,"field_id":field,"filter_type":2,"ty":ty,"condition":condition,"content":content})
}
fn fields() -> Vec<Field> {
    let make = |id: &str, ty: FieldType| {
        let mut f = Field::from_field_type(id, ty, false);
        f.id = id.into();
        f
    };
    vec![
        make("title", FieldType::RichText),
        make("number", FieldType::Number),
        choices::configure(
            make("choice", FieldType::SingleSelect),
            &[
                choices::Choice {
                    id: "one".into(),
                    name: "一,Unicode".into(),
                    color: 0,
                },
                choices::Choice {
                    id: "two".into(),
                    name: "二".into(),
                    color: 1,
                },
            ],
        )
        .unwrap(),
    ]
}
#[test]
fn original_seed_decisions_and_precise_arithmetic_with_overflow_guard() {
    let fields = fields();
    for (condition, content, expected) in [
        (0, "9007199254740993", "9007199254740993"),
        (2, "9007199254740993", "9007199254740994"),
        (3, "-2.5", "-3.5"),
    ] {
        let rules = Rules::parse(
            &json!([leaf("n", "number", 1, condition, content)]),
            &json!([]),
            &fields,
        )
        .unwrap();
        let seeds = rules.prefill(&fields).unwrap();
        assert_eq!(seeds["number"]["data"].to_string(), expected);
    }
    for (condition, content) in [
        (2, "79228162514264337593543950335"),
        (3, "-79228162514264337593543950335"),
    ] {
        assert!(
            Rules::parse(
                &json!([leaf("n", "number", 1, condition, content)]),
                &json!([]),
                &fields
            )
            .unwrap()
            .prefill(&fields)
            .unwrap()
            .is_empty()
        );
    }
    let rules = Rules::parse(
        &json!([
            leaf("t", "title", 0, 2, "Muse"),
            leaf("s", "choice", 3, 0, "two")
        ]),
        &json!([]),
        &fields,
    )
    .unwrap();
    let seeds = rules.prefill(&fields).unwrap();
    assert_eq!(seeds["title"]["data"].to_string(), "Muse");
    assert_eq!(
        choices::selected(&fields[2], Some(&seeds["choice"])).unwrap(),
        vec!["two"]
    );
}
#[test]
fn duplicate_field_filters_skip_seed_and_or_uses_first_branch_without_solver() {
    let fields = fields();
    let filters = json!([
        leaf("t", "title", 0, 2, "Muse"),
        leaf("u", "title", 0, 4, "Other")
    ]);
    assert!(
        Rules::parse(&filters, &json!([]), &fields)
            .unwrap()
            .prefill(&fields)
            .unwrap()
            .is_empty()
    );
    let filters = json!([{"id":"or","filter_type":1,"children":[leaf("t","title",0,0,"first"),leaf("u","title",0,0,"second")]}]);
    assert_eq!(
        Rules::parse(&filters, &json!([]), &fields)
            .unwrap()
            .prefill(&fields)
            .unwrap()["title"]["data"]
            .to_string(),
        "first"
    );
}
#[test]
fn unknown_number_format_is_read_only_without_destroying_metadata() {
    let mut f = fields().remove(1);
    let mut options = f
        .get_any_type_option(1)
        .unwrap_or_else(|| NumberTypeOption::default().into());
    options.insert("format".into(), collab::preclude::Any::BigInt(999));
    f = f.with_type_option_data(1, options);
    assert!(model::readers(&f).is_none());
    let mut known = fields().remove(1);
    known = known.with_type_option_data(
        1,
        NumberTypeOption {
            format: NumberFormat::Num,
            ..Default::default()
        }
        .into(),
    );
    assert!(model::readers(&known).is_some());
}
#[test]
fn explicit_cells_win_and_hidden_row_query_preserves_shared_rules_and_references() {
    futures::executor::block_on(async {
        let mut s = Session::open(&uuid::Uuid::new_v4().to_string(), None, None)
            .await
            .unwrap();
        let v = s.snapshot().await.unwrap()["views"][0].clone();
        s.command(serde_json::from_value(json!({"op":"configureViewRules","viewId":v["id"],"filters":[leaf("t","title",0,0,"Muse")],"sorts":[],"expectedRulesHash":v["rulesHash"],"expectedFieldsHash":v["fieldsHash"]})).unwrap()).await.unwrap();
        let view_id = v["id"].as_str().unwrap().to_string();
        let id = uuid::Uuid::new_v4().to_string();
        s.command(Command::AddRow {
            view_id: Some(view_id.clone()),
            row_id: id.clone(),
            cells: Default::default(),
        })
        .await
        .unwrap();
        assert_eq!(
            s.read_row(&view_id, &id).await.unwrap()["cells"]["title"]["value"],
            "Muse"
        );
        let hidden = uuid::Uuid::new_v4().to_string();
        s.command(Command::AddRow {
            view_id: Some(view_id.clone()),
            row_id: hidden.clone(),
            cells: std::collections::HashMap::from([("title".into(), json!("Other"))]),
        })
        .await
        .unwrap();
        let snap = s.snapshot().await.unwrap();
        assert_eq!(snap["views"][0]["rows"].as_array().unwrap().len(), 1);
        assert_eq!(snap["views"][0]["rowObjects"].as_array().unwrap().len(), 2);
        let record = s.read_row(&view_id, &hidden).await.unwrap();
        assert_eq!(record["cells"]["title"]["value"], "Other");
        s.command(Command::SetCell {
            row_id: hidden.clone(),
            field_id: "title".into(),
            value: json!("Muse"),
            expected_hash: record["cells"]["title"]["hash"].as_str().unwrap().into(),
            expected_field_hash: None,
        })
        .await
        .unwrap();
        assert_eq!(
            s.snapshot().await.unwrap()["views"][0]["rows"]
                .as_array()
                .unwrap()
                .len(),
            2
        );
        assert!(s.read_row("missing-view", &hidden).await.is_err());
        assert!(
            s.read_row(&view_id, &uuid::Uuid::new_v4().to_string())
                .await
                .is_err()
        );
    });
}
