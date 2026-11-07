use collab_database::{
    entity::FieldType,
    fields::{
        Field,
        number_type_option::{NumberFormat, NumberTypeOption},
    },
};
use serde_json::json;
#[test]
fn number_name_and_format_are_one_root_history_item_and_preserve_peer_row_edit() {
    use crate::{commands::Command, model, session::Session, tests::send};
    futures::executor::block_on(async {
        let mut a = Session::open(&uuid::Uuid::new_v4().to_string(), None, None).await.unwrap();
        a.command(serde_json::from_value(json!({"op":"createField","id":"amount","name":"金额","semanticType":"number"})).unwrap()).await.unwrap();
        let row = uuid::Uuid::new_v4().to_string();
        a.command(serde_json::from_value(json!({"op":"addRow","rowId":row,"cells":{"amount":"12345678901234567890.12345678"}})).unwrap()).await.unwrap();
        let mut b = Session::open(&a.object_id, Some(a.bundle().await.unwrap()), None).await.unwrap();
        let f = a.database.get_fields(None).into_iter().find(|f| f.id=="amount").unwrap();
        let before = serde_json::to_value(a.bundle().await.unwrap()).unwrap();
        for (name,format,hash) in [("",4,model::field_hash(&f)),("预算",3,model::field_hash(&f)),("预算",4,"stale".into())] {
            assert!(a.command(Command::ConfigureNumberField{field_id:"amount".into(),name:Some(name.into()),format,expected_field_hash:hash}).await.is_err());
            assert_eq!(serde_json::to_value(a.bundle().await.unwrap()).unwrap(),before);
        }
        a.command(Command::ConfigureNumberField{field_id:"amount".into(),name:Some("预算".into()),format:4,expected_field_hash:model::field_hash(&f)}).await.unwrap();
        send(&a,&mut b).await;
        let state=b.snapshot().await.unwrap();
        assert_eq!(state["views"][0]["columns"][3]["name"],"预算");
        assert_eq!(state["views"][0]["columns"][3]["numberOptions"]["format"],4);
        assert_eq!(state["views"][0]["rows"][0]["cells"]["amount"]["numberInput"],"12345678901234567890.12345678");
        b.command(serde_json::from_value(json!({"op":"setCell","rowId":row,"fieldId":"amount","value":"42.125","expectedHash":state["views"][0]["rows"][0]["cells"]["amount"]["hash"],"expectedFieldHash":state["views"][0]["columns"][3]["fieldHash"]})).unwrap()).await.unwrap();
        send(&b,&mut a).await;
        a.history(false).await.unwrap();
        let undo=a.snapshot().await.unwrap();
        assert_eq!(undo["views"][0]["columns"][3]["name"],"金额");
        assert_eq!(undo["views"][0]["columns"][3]["numberOptions"]["format"],0);
        assert_eq!(undo["views"][0]["rows"][0]["cells"]["amount"]["numberInput"],"42.125");
        send(&a,&mut b).await;
        assert_eq!(a.snapshot().await.unwrap()["views"],b.snapshot().await.unwrap()["views"]);
        let reopened=Session::open(&a.object_id,Some(a.bundle().await.unwrap()),None).await.unwrap();
        assert_eq!(reopened.snapshot().await.unwrap()["views"],a.snapshot().await.unwrap()["views"]);
    });
}
#[test]
fn long_currency_grouping_repeats_the_original_locale_pattern_to_decimal_capacity() {
    for (format, expected) in [
        (NumberFormat::USD, "$12,345,678,901,234,567,890.12"),
        (NumberFormat::EUR, "€12.345.678.901.234.567.890,12"),
        (NumberFormat::Rupee, "₹1,23,45,67,89,01,23,45,67,890.12"),
    ] {
        let mut options = NumberTypeOption::default();
        options.set_format(format);
        let field = Field::from_field_type("金额", FieldType::Number, false)
            .with_type_option_data(1, options.into());
        let cell = crate::model::write(&field, json!("12345678901234567890.12345678")).unwrap();
        assert_eq!(crate::model::readers(&field).unwrap().0.json_cell(&cell), json!(expected));
    }
}
#[test]
fn numeric_projection_keeps_exact_input_separate_from_original_money_display() {
    let mut field = Field::from_field_type("金额", FieldType::Number, false);
    let mut options = NumberTypeOption::default();
    options.set_format(NumberFormat::USD);
    field = field.with_type_option_data(1, options.into());
    let cell = crate::model::write(&field, json!("9007199254740993.123456789")).unwrap();
    let display = crate::model::readers(&field).unwrap().0.json_cell(&cell);
    assert_ne!(display, json!("9007199254740993.123456789"));
    assert_eq!(
        crate::numbers::input(&field, Some(&cell)).unwrap(),
        "9007199254740993.123456789"
    );
}
#[test]
fn new_numeric_writes_reject_partial_numbers_and_nonfinite_or_lossy_values() {
    let field = Field::from_field_type("数值", FieldType::Number, false);
    for value in [
        "123abc",
        "NaN",
        "Infinity",
        "1,234.56",
        "1e-29",
        "79228162514264337593543950336",
    ] {
        assert!(
            crate::model::write(&field, json!(value)).is_err(),
            "{value}"
        );
    }
    for value in [
        "0",
        "-0.001",
        ".125",
        "1e-28",
        "79228162514264337593543950335",
        "",
    ] {
        assert!(crate::model::write(&field, json!(value)).is_ok(), "{value}");
    }
}

#[test]
fn exact_numeric_boundary_has_no_partial_parse_or_rounding() {
    for (input, expected) in [
        (".125", "0.125"),
        ("-.125", "-0.125"),
        ("+1.2300", "1.2300"),
        ("1e3", "1000"),
        ("1.25E-2", "0.0125"),
        ("1e-28", "0.0000000000000000000000000001"),
        ("0", "0"),
        (" ", ""),
    ] {
        assert_eq!(
            crate::numbers::canonical(input).unwrap(),
            expected,
            "{input}"
        );
    }
    for input in [
        "1.12345678901234567890123456789",
        "1.12345678901234567890123456789e1",
        "1e999",
        "1e",
        "--1",
        "1_000",
        "１２３",
        "1..2",
        "$2",
        "1 2",
        "\nNaN",
    ] {
        assert!(crate::numbers::canonical(input).is_err(), "{input}");
    }
}
#[test]
fn unknown_original_numeric_value_and_options_remain_readonly_and_untouched() {
    use collab::preclude::Any;
    use collab_database::{rows::new_cell_builder, template::entity::CELL_DATA};
    let field = Field::from_field_type("数值", FieldType::Number, false);
    let mut cell = new_cell_builder(FieldType::Number);
    cell.insert(CELL_DATA.into(), Any::String("123abc".into()));
    let before = serde_json::to_vec(&cell).unwrap();
    assert!(crate::numbers::unresolved(&field, Some(&cell)));
    assert!(crate::model::write_existing(&field, json!("2"), Some(&cell)).is_err());
    assert_eq!(serde_json::to_vec(&cell).unwrap(), before);
    let mut option: collab_database::fields::TypeOptionData = NumberTypeOption::default().into();
    option.insert("format".into(), Any::BigInt(999));
    let field = field.with_type_option_data(1, option);
    assert!(crate::numbers::options(&field).is_none());
    assert!(crate::numbers::input(&field, None).is_none());
}

#[test]
fn original_number_options_keep_all_known_currency_amounts_separate_from_display() {
    for code in 0..=36 {
        let format = NumberFormat::from(code);
        if format.value() != code {
            continue;
        }
        let mut options = NumberTypeOption::default();
        options.set_format(format);
        let field = Field::from_field_type("数值", FieldType::Number, false)
            .with_type_option_data(1, options.into());
        let cell = crate::model::write(&field, json!("-1234.56789")).unwrap();
        assert_eq!(
            crate::numbers::input(&field, Some(&cell)).unwrap(),
            "-1234.56789",
            "format {code}"
        );
        assert!(
            !crate::model::readers(&field)
                .unwrap()
                .0
                .json_cell(&cell)
                .as_str()
                .unwrap()
                .is_empty(),
            "format {code}"
        );
    }
}
#[test]
fn number_commands_reject_invalid_or_stale_drafts_without_changing_original_bytes() {
    use crate::{commands::Command, model, session::Session};
    use std::collections::HashMap;
    futures::executor::block_on(async {
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
        let field = s
            .database
            .get_fields(None)
            .into_iter()
            .find(|f| f.id == "amount")
            .unwrap();
        s.command(Command::ConfigureNumberField {
            field_id: field.id.clone(),
            name: None,
            format: 1,
            expected_field_hash: model::field_hash(&field),
        })
        .await
        .unwrap();
        let row = uuid::Uuid::new_v4().to_string();
        s.command(Command::AddRow {
            row_id: row.clone(),
            view_id: None,
            cells: HashMap::from([("amount".into(), json!("9007199254740993.123456789"))]),
        })
        .await
        .unwrap();
        let state = s.snapshot().await.unwrap();
        let cell = &state["views"][0]["rows"][0]["cells"]["amount"];
        assert_eq!(cell["numberInput"], "9007199254740993.123456789");
        let hash = cell["hash"].as_str().unwrap().to_string();
        let field = s
            .database
            .get_fields(None)
            .into_iter()
            .find(|f| f.id == "amount")
            .unwrap();
        let before = serde_json::to_value(s.bundle().await.unwrap()).unwrap();
        for (value, field_hash) in [
            ("123abc", Some(model::field_hash(&field))),
            ("2", None),
            ("2", Some("stale".into())),
        ] {
            assert!(
                s.command(Command::SetCell {
                    row_id: row.clone(),
                    field_id: "amount".into(),
                    value: json!(value),
                    expected_hash: hash.clone(),
                    expected_field_hash: field_hash
                })
                .await
                .is_err()
            );
            assert_eq!(
                serde_json::to_value(s.bundle().await.unwrap()).unwrap(),
                before
            );
        }
        s.command(Command::SetCell {
            row_id: row.clone(),
            field_id: "amount".into(),
            value: json!("-1.25e-2"),
            expected_hash: hash,
            expected_field_hash: Some(model::field_hash(&field)),
        })
        .await
        .unwrap();
        assert_eq!(
            s.snapshot().await.unwrap()["views"][0]["rows"][0]["cells"]["amount"]["numberInput"],
            "-0.0125"
        );
        s.history(false).await.unwrap();
        assert_eq!(
            s.snapshot().await.unwrap()["views"][0]["rows"][0]["cells"]["amount"]["numberInput"],
            "9007199254740993.123456789"
        );
        let reopened = Session::open(&s.object_id, Some(s.bundle().await.unwrap()), None)
            .await
            .unwrap();
        assert_eq!(
            s.snapshot().await.unwrap()["views"],
            reopened.snapshot().await.unwrap()["views"]
        );
    });
}
