use crate::{commands::Command, dates, model, session::Session};
use collab_database::{
    entity::FieldType,
    fields::{Field, date_type_option::DateCellData},
    rows::Cell,
};
use serde_json::{Value, json};

fn field(zone: &str) -> Field {
    dates::configure(
        Field::from_field_type("日期", FieldType::DateTime, false),
        Some(zone),
    )
    .unwrap()
}
fn draft(start: &str, timed: bool, end: Option<&str>) -> Value {
    json!({"start":start,"end":end,"includeTime":timed,"isRange":end.is_some()})
}
#[test]
fn original_date_codec_civil_ranges_epoch_clear_and_hidden_time_roundtrip() {
    let f = field("Asia/Shanghai");
    let cell = model::write(&f, draft("2026-11-06", false, Some("2026-11-07"))).unwrap();
    let original = DateCellData::from(&cell);
    assert_eq!(original.timestamp, Some(1793894400));
    assert!(!original.include_time);
    assert!(original.is_range);
    assert_eq!(
        dates::projection(&f, Some(&cell)),
        json!({"start":"2026-11-06","end":"2026-11-07","includeTime":false,"isRange":true,"timezone":"Asia/Shanghai"})
    );
    let cell = model::write(&field("Etc/UTC"), draft("1969-12-31T23:59:59Z", true, None)).unwrap();
    assert_eq!(DateCellData::from(&cell).timestamp, Some(-1));
    let empty = model::write(&f, Value::Null).unwrap();
    assert!(DateCellData::from(&empty).timestamp.is_none());
    let epoch = model::write(&field("Etc/UTC"), draft("1970-01-01T00:00:00Z", true, None)).unwrap();
    assert_eq!(DateCellData::from(&epoch).timestamp, Some(0));
    let prior = Cell::from(&DateCellData::from_timestamp(1793928612));
    let mut before = dates::projection(&f, Some(&prior));
    before.as_object_mut().unwrap().remove("timezone");
    let kept = model::write_existing(&f, before, Some(&prior)).unwrap();
    assert_eq!(
        DateCellData::from(&kept).timestamp,
        DateCellData::from(&prior).timestamp
    );
    let open = model::write(
        &f,
        json!({"start":"2026-11-06","end":null,"includeTime":false,"isRange":true}),
    )
    .unwrap();
    assert!(DateCellData::from(&open).is_range);
    assert!(DateCellData::from(&open).end_timestamp.is_none());
}
#[test]
fn invalid_dates_dst_precision_and_wrong_offsets_are_never_coerced() {
    let (utc, ny) = (field("Etc/UTC"), field("America/New_York"));
    for value in [
        json!("not a date"),
        json!(123),
        json!({"start":"2026-01-01"}),
        draft("2026-02-30", false, None),
        draft("2026-1-1", false, None),
        draft("0000-01-01", false, None),
        draft("2026-01-01T00:00:00.123Z", true, None),
        draft("2026-01-01T00:00:60Z", true, None),
        draft("2026-01-01T00:00:00+08:00", true, None),
        draft("2026-11-06", false, Some("2026-11-05")),
    ] {
        assert!(model::write(&utc, value.clone()).is_err(), "{value}");
    }
    assert_eq!(
        model::write(&ny, draft("2026-03-08T02:30:00", true, None)).unwrap_err(),
        "DATE_LOCAL_TIME_GAP"
    );
    assert_eq!(
        model::write(&ny, draft("2026-11-01T01:30:00", true, None)).unwrap_err(),
        "DATE_LOCAL_TIME_AMBIGUOUS"
    );
    let early = model::write(&ny, draft("2026-11-01T01:30:00-04:00", true, None)).unwrap();
    let late = model::write(&ny, draft("2026-11-01T01:30:00-05:00", true, None)).unwrap();
    assert_eq!(
        DateCellData::from(&late).timestamp.unwrap()
            - DateCellData::from(&early).timestamp.unwrap(),
        3600
    );
    assert_eq!(
        model::write(&field("Pacific/Apia"), draft("2011-12-30", false, None)).unwrap_err(),
        "DATE_LOCAL_TIME_GAP"
    );
    assert!(
        dates::configure(
            Field::from_field_type("日期", FieldType::DateTime, false),
            Some("Mars/Unknown")
        )
        .is_err()
    );
}
#[test]
fn malformed_external_options_or_values_and_reminders_are_preserved_readonly() {
    let f = field("Etc/UTC");
    let mut cell = Cell::from(&DateCellData::from_timestamp(0));
    cell.insert("data".into(), "unparseable".into());
    assert!(dates::unresolved(&f, Some(&cell)));
    assert!(model::write_existing(&f, draft("2026-01-01", false, None), Some(&cell)).is_err());
    let mut reminder = DateCellData::from_timestamp(0);
    reminder.reminder_id = "original-reminder".into();
    assert!(dates::unresolved(&f, Some(&Cell::from(&reminder))));
    let mut bad = collab_database::fields::date_type_option::DateTypeOption::default_utc();
    bad.timezone_id = "invalid/unknown".into();
    let f = f.with_type_option_data(2, bad.into());
    assert!(model::readers(&f).is_none());
    for ts in [i64::MIN, i64::MAX, 8210266876799, -8334601228800] {
        let f = field("Pacific/Kiritimati");
        let cell = Cell::from(&DateCellData::from_timestamp(ts));
        assert!(dates::unresolved(&f, Some(&cell)));
        assert!(dates::projection(&f, Some(&cell)).is_null());
    }
    // Historical LMT has a seconds-based offset that RFC3339 cannot encode.
    // Keep an imported cell opaque instead of rounding it on the next save.
    let f = field("Asia/Shanghai");
    assert_eq!(
        model::write(&f, draft("1900-01-01T12:00:00", true, None)).unwrap_err(),
        "DATE_OFFSET_PRECISION_UNSUPPORTED"
    );
}

#[test]
fn date_commands_protect_schema_and_cell_and_original_row_undo_reopen_converge() {
    futures::executor::block_on(async {
        let id = uuid::Uuid::new_v4().to_string();
        let row = uuid::Uuid::new_v4().to_string();
        let mut a = Session::open(&id, None, None).await.unwrap();
        async fn command(s: &mut Session, v: Value) -> Value {
            s.command(serde_json::from_value(v).unwrap()).await.unwrap()
        }
        command(&mut a,json!({"op":"createField","id":"date","name":"计划日期","semanticType":"date","timezone":"Asia/Shanghai"})).await;
        command(&mut a, json!({"op":"addRow","rowId":row})).await;
        async fn edit(s: &mut Session, row: &str, value: Value) -> Value {
            let before = s.snapshot().await.unwrap();
            let field = before["views"][0]["columns"]
                .as_array()
                .unwrap()
                .iter()
                .find(|f| f["id"] == "date")
                .unwrap();
            json!({"op":"setCell","rowId":row,"fieldId":"date","value":value,"expectedHash":before["views"][0]["rows"][0]["cells"]["date"]["hash"],"expectedFieldHash":field["fieldHash"]})
        }
        let change = edit(&mut a, &row, draft("2026-11-06", false, None)).await;
        command(&mut a, change).await;
        let mut b = Session::open(&id, Some(a.bundle().await.unwrap()), None)
            .await
            .unwrap();
        let stale = edit(&mut a, &row, draft("2026-11-07", false, None)).await;
        let peer = edit(&mut b, &row, draft("2026-11-08", false, None)).await;
        command(&mut b, peer).await;
        crate::tests::send(&b, &mut a).await;
        assert_eq!(
            a.command(serde_json::from_value(stale).unwrap())
                .await
                .unwrap_err(),
            "CELL_CHANGED"
        );
        let undone = a.history(false).await.unwrap();
        assert_eq!(
            undone["views"][0]["rows"][0]["cells"]["date"]["value"]["start"],
            "2026-11-08"
        );
        crate::tests::send(&a, &mut b).await;
        let stale = edit(&mut b, &row, draft("2026-11-09", false, None)).await;
        let snapshot = a.snapshot().await.unwrap();
        let f = snapshot["views"][0]["columns"]
            .as_array()
            .unwrap()
            .iter()
            .find(|f| f["id"] == "date")
            .unwrap();
        command(&mut a,json!({"op":"configureDateField","fieldId":"date","name":"新日期","timezone":"America/New_York","expectedFieldHash":f["fieldHash"]})).await;
        crate::tests::send(&a, &mut b).await;
        assert_eq!(
            b.command(serde_json::from_value(stale).unwrap())
                .await
                .unwrap_err(),
            "FIELD_CHANGED"
        );
        let reopen = Session::open(&id, Some(b.bundle().await.unwrap()), None)
            .await
            .unwrap();
        assert_eq!(
            a.snapshot().await.unwrap()["views"],
            reopen.snapshot().await.unwrap()["views"]
        );
        let invalid:Command=serde_json::from_value(json!({"op":"createField","id":"bad","name":"无效","semanticType":"date","timezone":"Unknown"})).unwrap();
        let before = a.snapshot().await.unwrap();
        assert_eq!(a.command(invalid).await.unwrap_err(), "INVALID_TIMEZONE");
        assert_eq!(a.snapshot().await.unwrap(), before);
    });
}
