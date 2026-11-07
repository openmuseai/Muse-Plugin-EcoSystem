//! Bounded protocol boundary over the original AppFlowy WS v2 protobuf/types.
//! No content schema, credentials, socket or persistence enters this module.
use appflowy_proto::{
    AccessChangedReason, ClientMessage, Rid, ServerMessage, UpdateFlags, WorkspaceNotification, pb,
};
use base64::{Engine, engine::general_purpose::STANDARD as B64};
use collab::preclude::{StateVector, Update, updates::decoder::Decode, updates::encoder::Encode};
use collab_entity::CollabType;
use prost::Message;
use serde_json::{Value, json};
mod presence;
pub const LIMIT: usize = 8 * 1024 * 1024;
pub type Result<T> = std::result::Result<T, String>;
fn string<'a>(v: &'a Value, key: &str) -> Result<&'a str> {
    v.get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("INVALID_REQUEST:{key}"))
}
fn bytes(v: &Value, key: &str, max: usize) -> Result<Vec<u8>> {
    let text = string(v, key)?;
    if text.len() > max * 4 / 3 + 4 {
        return Err("QUOTA_EXCEEDED".into());
    }
    let data = B64.decode(text).map_err(|_| "INVALID_BASE64")?;
    if data.len() > max {
        return Err("QUOTA_EXCEEDED".into());
    }
    Ok(data)
}
fn kind(value: i64) -> Result<CollabType> {
    if !(0..=5).contains(&value) {
        return Err("UNSUPPORTED_COLLAB_TYPE".into());
    }
    Ok(CollabType::from(value as i32))
}
fn rid(text: &str) -> Result<Rid> {
    let mut parts = text.split('-');
    let timestamp = parts
        .next()
        .ok_or("INVALID_RID")?
        .parse::<u64>()
        .map_err(|_| "INVALID_RID")?;
    let seq_no = parts
        .next()
        .ok_or("INVALID_RID")?
        .parse::<u16>()
        .map_err(|_| "INVALID_RID")?;
    if parts.next().is_some() {
        return Err("INVALID_RID".into());
    }
    Ok(Rid::new(timestamp, seq_no))
}
fn validate_rid(value: &Option<pb::Rid>) -> Result<()> {
    let rid = value.as_ref().ok_or("MISSING_RID")?;
    if rid.counter > u16::MAX as u32 {
        return Err("INVALID_RID".into());
    }
    Ok(())
}
pub fn encode_client(value: &Value) -> Result<Vec<u8>> {
    let object_id =
        uuid::Uuid::parse_str(string(value, "objectId")?).map_err(|_| "INVALID_OBJECT_ID")?;
    let collab_type = kind(
        value
            .get("collabType")
            .and_then(Value::as_i64)
            .ok_or("INVALID_COLLAB_TYPE")?,
    )?;
    let message = match string(value, "kind")? {
        "manifest" => {
            let vector = bytes(value, "stateVector", 65536)?;
            StateVector::decode_v1(&vector).map_err(|_| "INVALID_STATE_VECTOR")?;
            ClientMessage::Manifest {
                object_id,
                collab_type,
                last_message_id: rid(value
                    .get("lastMessageId")
                    .and_then(Value::as_str)
                    .unwrap_or("0-0"))?,
                state_vector: vector,
            }
        }
        "update" => {
            let update = bytes(value, "update", LIMIT)?;
            Update::decode_v1(&update).map_err(|_| "INVALID_UPDATE")?;
            ClientMessage::Update {
                object_id,
                collab_type,
                flags: UpdateFlags::Lib0v1,
                update,
            }
        }
        "awareness" => {
            let awareness = bytes(value, "awareness", 16384)?;
            presence::validate_awareness(&awareness)?;
            ClientMessage::AwarenessUpdate {
                object_id,
                collab_type,
                awareness,
            }
        }
        _ => return Err("UNSUPPORTED_MESSAGE".into()),
    };
    let bytes = message.into_bytes().map_err(|_| "ENCODE_FAILED")?;
    if bytes.len() > LIMIT {
        return Err("QUOTA_EXCEEDED".into());
    }
    Ok(bytes)
}
pub fn decode_server(bytes: &[u8]) -> Result<Value> {
    if bytes.len() > LIMIT {
        return Err("QUOTA_EXCEEDED".into());
    }
    // The upstream conversion narrows uint32 flags/counters. Validate the
    // original generated representation before invoking those conversions.
    let original = pb::Message::decode(bytes).map_err(|_| "INVALID_PROTOBUF")?;
    if let Some(pb::message::Payload::CollabMessage(message)) = &original.payload {
        if !(message.collab_type == CollabType::Unknown as i32
            && matches!(
                message.data,
                Some(pb::collab_message::Data::AwarenessUpdate(_))
            ))
        {
            kind(message.collab_type as i64)?;
        }
        match &message.data {
            Some(pb::collab_message::Data::SyncRequest(value)) => {
                validate_rid(&value.last_message_id)?;
                if value.state_vector.len() > 65536 {
                    return Err("QUOTA_EXCEEDED".into());
                }
            }
            Some(pb::collab_message::Data::Update(value)) => {
                validate_rid(&value.message_id)?;
                if value.flags > 1 {
                    return Err("UNSUPPORTED_ENCODING".into());
                }
            }
            Some(pb::collab_message::Data::AwarenessUpdate(value)) => {
                presence::validate_awareness(&value.payload)?;
            }
            _ => {}
        }
    }
    let message = ServerMessage::from_bytes(bytes).map_err(|_| "INVALID_SERVER_MESSAGE")?;
    Ok(match message {
        ServerMessage::Manifest {
            object_id,
            collab_type,
            last_message_id,
            state_vector,
        } => {
            StateVector::decode_v1(&state_vector).map_err(|_| "INVALID_STATE_VECTOR")?;
            json!({"kind":"manifest","objectId":object_id,"collabType":collab_type as i32,"lastMessageId":last_message_id.to_string(),"stateVector":B64.encode(state_vector)})
        }
        ServerMessage::Update {
            object_id,
            collab_type,
            flags,
            last_message_id,
            update,
        } => {
            let decoded = match flags {
                UpdateFlags::Lib0v1 => Update::decode_v1(&update),
                UpdateFlags::Lib0v2 => Update::decode_v2(&update),
            }
            .map_err(|_| "INVALID_UPDATE")?;
            let update = match flags {
                UpdateFlags::Lib0v1 => update.to_vec(),
                UpdateFlags::Lib0v2 => decoded.encode_v1(),
            };
            if update.len() > LIMIT {
                return Err("QUOTA_EXCEEDED".into());
            }
            json!({"kind":"update","objectId":object_id,"collabType":collab_type as i32,"lastMessageId":last_message_id.to_string(),"encoding":"yrs.update-v1","update":B64.encode(update)})
        }
        ServerMessage::AwarenessUpdate {
            object_id,
            collab_type,
            awareness,
        } => {
            json!({"kind":"awareness","objectId":object_id,"collabType":collab_type as i32,"awareness":B64.encode(awareness)})
        }
        ServerMessage::AccessChanges {
            object_id,
            collab_type,
            can_read,
            can_write,
            reason,
        } => {
            json!({"kind":"access","objectId":object_id,"collabType":collab_type as i32,"canRead":can_read,"canWrite":can_write,"reason":match reason { AccessChangedReason::PermissionDenied=>"denied", AccessChangedReason::ObjectDeleted=>"deleted" }})
        }
        ServerMessage::Notification { notification } => match notification {
            WorkspaceNotification::UserProfileChange { uid, name, email } => {
                json!({"kind":"notification","event":"profile","uid":uid.to_string(),"name":name,"email":email})
            }
            WorkspaceNotification::ObjectAccessChanged { object_id, reason } => {
                json!({"kind":"notification","event":"permission","objectId":object_id,"reason":reason.to_string()})
            }
        },
    })
}
pub fn execute(request: &Value) -> Result<Value> {
    if string(request, "action")?.starts_with("presence") {
        return presence::execute(request);
    }
    match string(request, "action")? {
        "encode" => Ok(
            json!({"frame":B64.encode(encode_client(request.get("message").ok_or("MISSING_MESSAGE")?)?)}),
        ),
        "decode" => decode_server(&bytes(request, "frame", LIMIT)?),
        _ => Err("UNSUPPORTED_ACTION".into()),
    }
}
pub fn call_json(input: &str) -> String {
    let response = if input.len() > LIMIT * 2 {
        Err("QUOTA_EXCEEDED".into())
    } else {
        serde_json::from_str(input)
            .map_err(|_| "INVALID_JSON".into())
            .and_then(|v| execute(&v))
    };
    match response {
        Ok(data) => json!({"ok":true,"data":data}).to_string(),
        Err(error) => json!({"ok":false,"error":error}).to_string(),
    }
}
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub fn muse_appflowy_realtime_call_json(input: &str) -> String {
    call_json(input)
}
#[cfg(not(target_arch = "wasm32"))]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn muse_appflowy_realtime_call(
    input: *const std::ffi::c_char,
) -> *mut std::ffi::c_char {
    let response = if input.is_null() {
        json!({"ok":false,"error":"INVALID_INPUT"}).to_string()
    } else {
        match unsafe { std::ffi::CStr::from_ptr(input) }.to_str() {
            Ok(input) => call_json(input),
            Err(_) => json!({"ok":false,"error":"INVALID_UTF8"}).to_string(),
        }
    };
    std::ffi::CString::new(response).unwrap().into_raw()
}
#[cfg(not(target_arch = "wasm32"))]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn muse_appflowy_realtime_free(output: *mut std::ffi::c_char) {
    if !output.is_null() {
        drop(unsafe { std::ffi::CString::from_raw(output) });
    }
}
#[cfg(test)]
mod tests;
