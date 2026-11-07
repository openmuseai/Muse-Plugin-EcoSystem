//! Original Yrs Awareness with an injected monotonic clock and bounded room state.
//! Presence is transient; it never enters a document/row update or snapshot store.
use super::{Result, bytes, string};
use base64::{Engine, engine::general_purpose::STANDARD as B64};
use collab::preclude::{
    Doc, OffsetKind, Options,
    encoding::read::Read,
    sync::Awareness,
    updates::{
        decoder::{Decode, DecoderV1},
        encoder::Encode,
    },
};
use serde_json::{Value, json};
use std::{
    collections::{HashMap, HashSet},
    sync::{
        Arc, LazyLock, Mutex,
        atomic::{AtomicU64, Ordering},
    },
};
struct Presence {
    object_id: String,
    client_id: u64,
    now: Arc<AtomicU64>,
    awareness: Awareness,
    known: HashSet<u64>,
}
static ROOMS: LazyLock<Mutex<HashMap<String, Presence>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
const CAPACITY: usize = 1024;
const EXPIRY: u64 = 30_000;
pub fn validate_awareness(data: &[u8]) -> Result<()> {
    if data.len() > 16384 {
        return Err("QUOTA_EXCEEDED".into());
    }
    let mut decoder = DecoderV1::from(data);
    let count: u64 = decoder.read_var().map_err(|_| "INVALID_AWARENESS")?;
    if count > 128 {
        return Err("PRESENCE_CAPACITY".into());
    }
    let update = collab::preclude::sync::AwarenessUpdate::decode_v1(data)
        .map_err(|_| "INVALID_AWARENESS")?;
    for entry in update.clients.values() {
        if entry.json.len() > 8192 {
            return Err("QUOTA_EXCEEDED".into());
        }
        let value: Value =
            serde_json::from_str(&entry.json).map_err(|_| "INVALID_AWARENESS_JSON")?;
        if !value.is_null() && !value.is_object() {
            return Err("INVALID_AWARENESS_STATE".into());
        }
    }
    Ok(())
}
impl Presence {
    fn advance(&self, v: &Value) -> Result<u64> {
        let now = v
            .get("nowMs")
            .and_then(Value::as_u64)
            .filter(|n| *n <= 9_007_199_254_740_991)
            .ok_or("INVALID_CLOCK")?;
        self.now.fetch_max(now, Ordering::Relaxed);
        Ok(self.now.load(Ordering::Relaxed))
    }
    fn snapshot(&self) -> Value {
        let now = self.now.load(Ordering::Relaxed);
        let mut clients=self.awareness.iter().filter_map(|(id,state)|{
            let raw=state.data?;
            if now.saturating_sub(state.last_updated)>EXPIRY {return None;}
            let value:Value=serde_json::from_str(&raw).ok()?;
            Some(json!({"clientId":id.to_string(),"local":id==self.client_id,"clock":state.clock,"state":value}))
        }).collect::<Vec<_>>();
        clients.sort_by(|a, b| a["clientId"].as_str().cmp(&b["clientId"].as_str()));
        json!({"objectId":self.object_id,"clientId":self.client_id.to_string(),"clients":clients,"expiryMs":EXPIRY})
    }
    fn local_update(&self) -> Result<Value> {
        let update = self
            .awareness
            .update_with_clients([self.client_id])
            .map_err(|_| "PRESENCE_STATE_REQUIRED")?
            .encode_v1();
        validate_awareness(&update)?;
        let mut state = self.snapshot();
        state["awareness"] = json!(B64.encode(update));
        Ok(state)
    }
}
pub fn execute(value: &Value) -> Result<Value> {
    let action = string(value, "action")?;
    let mut rooms = ROOMS.lock().map_err(|_| "ENGINE_POISONED")?;
    if action == "presenceOpen" {
        if rooms.len() >= 128 {
            return Err("SESSION_LIMIT".into());
        }
        let object_id = string(value, "objectId")?;
        uuid::Uuid::parse_str(object_id).map_err(|_| "INVALID_OBJECT_ID")?;
        let client_id = string(value, "clientId")?
            .parse::<u64>()
            .map_err(|_| "INVALID_CLIENT_ID")?;
        if client_id == 0 {
            return Err("INVALID_CLIENT_ID".into());
        }
        let now = Arc::new(AtomicU64::new(0));
        let clock = now.clone();
        let awareness = Awareness::with_clock(
            Doc::with_options(Options {
                client_id,
                offset_kind: OffsetKind::Utf16,
                ..Options::default()
            }),
            move || clock.load(Ordering::Relaxed),
        );
        let p = Presence {
            object_id: object_id.into(),
            client_id,
            now,
            awareness,
            known: HashSet::from([client_id]),
        };
        p.advance(value)?;
        let handle = uuid::Uuid::new_v4().to_string();
        let mut state = p.snapshot();
        state["handle"] = json!(handle);
        rooms.insert(handle, p);
        return Ok(state);
    }
    let handle = string(value, "handle")?;
    if action == "presenceClose" {
        rooms.remove(handle);
        return Ok(json!({"closed":true}));
    }
    let p = rooms.get_mut(handle).ok_or("SESSION_CLOSED")?;
    if string(value, "objectId")? != p.object_id {
        return Err("PRESENCE_SCOPE_MISMATCH".into());
    }
    p.advance(value)?;
    match action {
        "presenceSnapshot" => Ok(p.snapshot()),
        "presenceSet" => {
            let state = value.get("state").ok_or("MISSING_STATE")?;
            if !state.is_object() || state.to_string().len() > 7680 {
                return Err("INVALID_AWARENESS_STATE".into());
            }
            p.awareness
                .set_local_state(state)
                .map_err(|_| "INVALID_AWARENESS_STATE")?;
            p.local_update()
        }
        "presenceLeave" => {
            p.awareness.clean_local_state();
            p.local_update()
        }
        "presenceApply" => {
            let raw = bytes(value, "awareness", 16384)?;
            validate_awareness(&raw)?;
            let mut update = collab::preclude::sync::AwarenessUpdate::decode_v1(&raw)
                .map_err(|_| "INVALID_AWARENESS")?;
            update.clients.remove(&p.client_id); // another packet can never overwrite our local slot
            let extra = update
                .clients
                .keys()
                .filter(|id| !p.known.contains(id))
                .count();
            if p.known.len() + extra > CAPACITY {
                return Err("PRESENCE_CAPACITY".into());
            }
            p.known.extend(update.clients.keys());
            p.awareness
                .apply_update(update)
                .map_err(|_| "INVALID_AWARENESS")?;
            Ok(p.snapshot())
        }
        _ => Err("UNSUPPORTED_ACTION".into()),
    }
}
