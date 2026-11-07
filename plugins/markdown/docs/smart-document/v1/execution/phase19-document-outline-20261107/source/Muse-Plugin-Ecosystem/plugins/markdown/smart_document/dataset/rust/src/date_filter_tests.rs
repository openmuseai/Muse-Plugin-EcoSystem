use crate::{commands::Command, date_filters as df, dates, model, session::Session};
use collab_database::{entity::FieldType, fields::Field};
use serde_json::{Value, json};
fn field(zone: &str) -> Field {
    let mut f = dates::configure(
        Field::from_field_type("日期", FieldType::DateTime, false),
        Some(zone),
    )
    .unwrap();
    f.id = "date".into();
    f
}
fn rule(condition: i64, content: Value) -> Value {
    json!({"id":"date-rule","filter_type":2,"field_id":"date","ty":2,"condition":condition,"content":content})
}
fn parsed(
    f: &Field,
    c: i64,
    value: Value,
) -> (
    muse_appflowy_view_rules::entities::DateFilterPB,
    chrono_tz::Tz,
) {
    let normalized = df::normalize(&json!([rule(c, value)]), &[f.clone()]).unwrap();
    df::parse(f, c, normalized[0]["content"].as_str().unwrap()).unwrap()
}
#[test]
fn calendar_filter_uses_field_zone_and_inclusive_normalized_range() {
    let f = field("Asia/Shanghai");
    let cell = model::write(
        &f,
        json!({"start":"2026-11-07T00:30:00+08:00","end":null,"includeTime":true,"isRange":false}),
    )
    .unwrap();
    for (condition, content, expected) in [
        (0, json!({"timestamp":"2026-11-07"}), true),
        (0, json!({"timestamp":"2026-11-06"}), false),
        (1, json!({"timestamp":"2026-11-07"}), false),
        (2, json!({"timestamp":"2026-11-06"}), true),
        (3, json!({"timestamp":"2026-11-07"}), true),
        (4, json!({"timestamp":"2026-11-07"}), true),
        (5, json!({"start":"2026-11-08","end":"2026-11-07"}), true),
        (5, json!({"start":"2026-11-08","end":"2026-11-09"}), false),
    ] {
        let (filter, tz) = parsed(&f, condition, content);
        assert_eq!(
            df::visible(&f, &filter, tz, Some(&cell)).unwrap(),
            Some(expected)
        );
    }
}
#[test]
fn siyuan_open_range_end_is_empty_nonrange_end_uses_start() {
    let f = field("Etc/UTC");
    for (is_range, end, empty) in [
        (true, None, true),
        (true, Some("2026-11-08"), false),
        (false, None, false),
    ] {
        let cell = model::write(
            &f,
            json!({"start":"2026-11-07","end":end,"includeTime":false,"isRange":is_range}),
        )
        .unwrap();
        for (condition, expected) in [(14, empty), (15, !empty)] {
            let (filter, tz) = parsed(&f, condition, json!({}));
            assert_eq!(
                df::visible(&f, &filter, tz, Some(&cell)).unwrap(),
                Some(expected)
            );
        }
    }
}
#[test]
fn civil_filter_handles_dst_midnight_gap_epoch_and_rejects_wholly_skipped_day() {
    for (zone, day) in [
        ("America/Sao_Paulo", "2018-11-04"),
        ("America/New_York", "2026-03-08"),
        ("America/New_York", "2026-11-01"),
        ("Etc/UTC", "1970-01-01"),
        ("Etc/UTC", "0001-01-01"),
        ("Etc/UTC", "9999-12-31"),
    ] {
        let f = field(zone);
        let (filter, tz) = parsed(&f, 0, json!({"timestamp":day}));
        let dt = dates::valid_instant(filter.timestamp.unwrap(), tz).unwrap();
        assert_eq!(dt.format("%Y-%m-%d").to_string(), day);
    }
    let apia = field("Pacific/Apia");
    assert!(
        df::normalize(
            &json!([rule(0, json!({"timestamp":"2011-12-30"}))]),
            &[apia]
        )
        .is_err()
    );
    let f = field("Etc/UTC");
    for bad in [
        json!({"timestamp":"2026-02-30"}),
        json!({"timestamp":"2026-1-1"}),
        json!({"timestamp":"0000-01-01"}),
        json!({"timestamp":0}),
        json!({"timestamp":"2026-01-01","unknown":true}),
    ] {
        assert!(df::normalize(&json!([rule(0, bad)]), &[f.clone()]).is_err());
    }
    for raw in [
        r#"{"timestamp":9223372036854775807}"#,
        r#"{"timestamp":1.5}"#,
        r#"{"unknown":1}"#,
        "null",
        "garbage",
    ] {
        assert!(df::parse(&f, 0, raw).is_err(), "{raw}");
    }
    let (filter, tz) = df::parse(&f, 0, r#"{"timestamp":0}"#).unwrap();
    assert_eq!(filter.timestamp, Some(0));
    assert_eq!(df::visible(&f, &filter, tz, None).unwrap(), Some(false));
}
#[test]
fn unconfigured_known_date_condition_is_disabled_not_an_unknown_rule() {
    let f = field("Etc/UTC");
    for c in [0, 1, 2, 3, 4, 5, 8, 9, 10, 11, 12, 13] {
        let (filter, tz) = parsed(&f, c, json!({}));
        assert_eq!(df::visible(&f, &filter, tz, None).unwrap(), None);
    }
    assert!(df::parse(&f, 16, "{}").is_err());
}
#[test]
fn date_rules_roundtrip_original_storage_shared_root_history_and_hidden_dependencies() {
    futures::executor::block_on(async {
        let mut s = Session::open(&uuid::Uuid::new_v4().to_string(), None, None)
            .await
            .unwrap();
        s.command(Command::CreateField {
            id: "date".into(),
            name: "日期".into(),
            semantic_type: "date".into(),
            options: vec![],
            timezone: Some("Asia/Shanghai".into()),
        })
        .await
        .unwrap();
        let row_id = uuid::Uuid::new_v4().to_string();
        s.command(Command::AddRow {
            view_id: None,
            row_id: row_id.clone(),
            cells: std::collections::HashMap::from([(
                "date".into(),
                json!({"start":"2026-11-07","end":null,"includeTime":false,"isRange":false}),
            )]),
        })
        .await
        .unwrap();
        let v = s.snapshot().await.unwrap()["views"][0].clone();
        let result=s.command(serde_json::from_value(json!({"op":"configureViewRules","viewId":v["id"],"filters":[rule(0,json!({"timestamp":"2026-11-08"}))],"sorts":[],"expectedRulesHash":v["rulesHash"],"expectedFieldsHash":v["fieldsHash"]})).unwrap()).await.unwrap();
        let v = &result["views"][0];
        assert_eq!(v["rulesReady"], true);
        assert_eq!(v["rows"].as_array().unwrap().len(), 0);
        assert_eq!(v["rowObjects"][0]["id"], row_id);
        assert!(v["filters"][0]["content"].is_string());
        assert_eq!(
            v["dateFilterInputs"]["date-rule"]["timestamp"],
            "2026-11-08"
        );
        let mut peer = Session::open(&s.object_id, Some(s.bundle().await.unwrap()), None)
            .await
            .unwrap();
        assert_eq!(
            peer.snapshot().await.unwrap()["views"][0]["rows"]
                .as_array()
                .unwrap()
                .len(),
            0
        );
        s.history(false).await.unwrap();
        crate::tests::send(&s, &mut peer).await;
        assert_eq!(
            peer.snapshot().await.unwrap()["views"][0]["rows"][0]["id"],
            row_id
        );
    });
}

#[test]
fn original_date_seed_obeys_zone_and_declines_unrepresentable_or_empty_conditions() {
    for (zone, day, condition, want) in [
        ("America/New_York", "2026-03-08", 1, Some("2026-03-07")),
        ("America/New_York", "2026-03-08", 2, Some("2026-03-09")),
        ("Etc/UTC", "9999-12-31", 2, None),
        ("Etc/UTC", "0001-01-01", 1, None),
        ("Etc/UTC", "2026-11-07", 7, None),
    ] {
        let f = field(zone);
        let content = df::normalize(
            &json!([rule(condition, json!({"timestamp":day}))]),
            &[f.clone()],
        )
        .unwrap();
        let rules = crate::view_rules::Rules::parse(&content, &json!([]), &[f.clone()]).unwrap();
        let seeds = rules.prefill(&[f.clone()]).unwrap();
        match want {
            Some(want) => assert_eq!(dates::projection(&f, Some(&seeds["date"]))["start"], want),
            None => assert!(seeds.is_empty()),
        }
    }
}
