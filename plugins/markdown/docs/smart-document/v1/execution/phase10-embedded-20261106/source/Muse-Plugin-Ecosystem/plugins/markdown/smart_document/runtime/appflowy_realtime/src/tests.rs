use super::*;
#[test]
fn original_client_types_and_stable_ids_roundtrip() {
    let id = uuid::Uuid::parse_str("041c01d0-831a-408a-b8fa-190d40dd9e94").unwrap();
    for ty in [0, 1, 4] {
        let frame=encode_client(&json!({"kind":"manifest","objectId":id,"collabType":ty,"lastMessageId":"18446744073709551615-65535","stateVector":B64.encode([0])})).unwrap();
        match ClientMessage::from_bytes(&frame).unwrap() {
            ClientMessage::Manifest {
                object_id,
                collab_type,
                last_message_id,
                state_vector,
            } => {
                assert_eq!(object_id, id);
                assert_eq!(collab_type as i32, ty);
                assert_eq!(last_message_id.to_string(), "18446744073709551615-65535");
                assert_eq!(state_vector, vec![0]);
            }
            _ => panic!("wrong message"),
        }
    }
    assert_eq!(rid("0-0-extra").unwrap_err(), "INVALID_RID");
}
#[test]
fn original_server_updates_v1_v2_keep_deletes_and_json_integer_identity() {
    use collab::preclude::{Doc, GetString, OffsetKind, Options, ReadTxn, Text, Transact};
    let doc = Doc::with_options(Options {
        offset_kind: OffsetKind::Utf16,
        ..Options::default()
    });
    let text = doc.get_or_insert_text("text");
    text.insert(&mut doc.transact_mut(), 0, "协作😀");
    text.remove_range(&mut doc.transact_mut(), 0, 1);
    for flag in [UpdateFlags::Lib0v1, UpdateFlags::Lib0v2] {
        let tx = doc.transact();
        let update = match flag {
            UpdateFlags::Lib0v1 => tx.encode_state_as_update_v1(&StateVector::default()),
            UpdateFlags::Lib0v2 => tx.encode_state_as_update_v2(&StateVector::default()),
        };
        drop(tx);
        let server = ServerMessage::Update {
            object_id: uuid::Uuid::nil(),
            collab_type: CollabType::Document,
            flags: flag,
            last_message_id: Rid::new(u64::MAX, u16::MAX),
            update: update.into(),
        };
        let json = decode_server(&server.into_bytes().unwrap()).unwrap();
        assert_eq!(json["lastMessageId"], "18446744073709551615-65535");
        let target = Doc::with_options(Options {
            offset_kind: OffsetKind::Utf16,
            ..Options::default()
        });
        target
            .transact_mut()
            .apply_update(
                Update::decode_v1(&B64.decode(json["update"].as_str().unwrap()).unwrap()).unwrap(),
            )
            .unwrap();
        assert_eq!(
            target
                .get_or_insert_text("text")
                .get_string(&target.transact()),
            "作😀"
        );
    }
}
#[test]
fn original_protobuf_narrowing_and_frame_limits_are_checked_before_conversion() {
    let frame = ServerMessage::Update {
        object_id: uuid::Uuid::nil(),
        collab_type: CollabType::Document,
        flags: UpdateFlags::Lib0v1,
        last_message_id: Rid::default(),
        update: vec![0, 0].into(),
    }
    .into_bytes()
    .unwrap();
    let mutate = |flag: u32, counter: u32, ty: i32| {
        let mut raw = pb::Message::decode(&*frame).unwrap();
        if let Some(pb::message::Payload::CollabMessage(m)) = &mut raw.payload {
            m.collab_type = ty;
            if let Some(pb::collab_message::Data::Update(u)) = &mut m.data {
                u.flags = flag;
                u.message_id.as_mut().unwrap().counter = counter;
            }
        }
        raw.encode_to_vec()
    };
    assert_eq!(
        decode_server(&mutate(256, 0, 0)).unwrap_err(),
        "UNSUPPORTED_ENCODING"
    );
    assert_eq!(
        decode_server(&mutate(0, 65536, 0)).unwrap_err(),
        "INVALID_RID"
    );
    assert_eq!(
        decode_server(&mutate(0, 0, 260)).unwrap_err(),
        "UNSUPPORTED_COLLAB_TYPE"
    );
    assert_eq!(
        decode_server(&vec![0; LIMIT + 1]).unwrap_err(),
        "QUOTA_EXCEEDED"
    );
}

#[test]
fn original_awareness_clock_expiry_scope_and_null_leave_are_transient() {
    let id = "041c01d0-831a-408a-b8fa-190d40dd9e94";
    let a =
        execute(&json!({"action":"presenceOpen","objectId":id,"clientId":"7","nowMs":0})).unwrap();
    let b =
        execute(&json!({"action":"presenceOpen","objectId":id,"clientId":"8","nowMs":0})).unwrap();
    let local=execute(&json!({"action":"presenceSet","handle":a["handle"],"objectId":id,"nowMs":10,"state":{"selection":null}})).unwrap();
    let remote=execute(&json!({"action":"presenceApply","handle":b["handle"],"objectId":id,"nowMs":20,"awareness":local["awareness"]})).unwrap();
    assert_eq!(remote["clients"][0]["clientId"], "7");
    let expired = execute(
        &json!({"action":"presenceSnapshot","handle":b["handle"],"objectId":id,"nowMs":30021}),
    )
    .unwrap();
    assert!(expired["clients"].as_array().unwrap().is_empty());
    let left = execute(
        &json!({"action":"presenceLeave","handle":a["handle"],"objectId":id,"nowMs":30022}),
    )
    .unwrap();
    let remote=execute(&json!({"action":"presenceApply","handle":b["handle"],"objectId":id,"nowMs":30023,"awareness":left["awareness"]})).unwrap();
    assert!(remote["clients"].as_array().unwrap().is_empty());
    assert_eq!(execute(&json!({"action":"presenceSnapshot","handle":b["handle"],"objectId":uuid::Uuid::nil(),"nowMs":40000})).unwrap_err(),"PRESENCE_SCOPE_MISMATCH");
    for room in [a, b] {
        execute(&json!({"action":"presenceClose","handle":room["handle"]})).unwrap();
    }
    // Huge declared counts are rejected before upstream HashMap allocation.
    assert_eq!(
        presence::validate_awareness(&[255, 255, 255, 255, 15]).unwrap_err(),
        "PRESENCE_CAPACITY"
    );
}
