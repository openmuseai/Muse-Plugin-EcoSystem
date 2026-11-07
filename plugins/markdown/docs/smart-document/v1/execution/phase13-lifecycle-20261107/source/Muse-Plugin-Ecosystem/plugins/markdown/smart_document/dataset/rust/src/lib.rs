//! Independent Dataset domain over original AppFlowy Database and row CRDTs.
//! UI, HTTP authorization and persistent stores do not enter this core.
use base64::{Engine, engine::general_purpose::STANDARD as B64};
use serde_json::{Value, json};
use std::{
    collections::HashMap,
    sync::{LazyLock, Mutex},
};
mod choices;
mod commands;
mod dates;
mod model;
mod reader;
mod session;
use session::Session;
type Result<T> = std::result::Result<T, String>;
fn err(e: impl std::fmt::Display) -> String {
    e.to_string()
}
fn field<'a>(v: &'a Value, key: &str) -> Result<&'a str> {
    v.get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("INVALID_REQUEST:{key}"))
}
static SESSIONS: LazyLock<Mutex<HashMap<String, Session>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));
fn execute(request: Value) -> Result<Value> {
    futures::executor::block_on(async {
        let mut sessions = SESSIONS.lock().map_err(|_| "ENGINE_POISONED")?;
        let action = field(&request, "action")?;
        if action == "open" {
            if sessions.len() >= 128 {
                return Err("SESSION_LIMIT".into());
            }
            let bundle = request
                .get("bundle")
                .filter(|v| !v.is_null())
                .cloned()
                .map(serde_json::from_value)
                .transpose()
                .map_err(err)?;
            let session = Session::open(field(&request, "objectId")?, bundle, None).await?;
            let mut state = session.snapshot().await?;
            let handle = uuid::Uuid::new_v4().to_string();
            state["handle"] = json!(handle);
            sessions.insert(handle, session);
            return Ok(state);
        }
        let handle = field(&request, "handle")?;
        if action == "close" {
            sessions.remove(handle);
            return Ok(json!({"closed":true}));
        }
        let session = sessions.get_mut(handle).ok_or("SESSION_CLOSED")?;
        match action {
            "snapshot" => session.snapshot().await,
            "command" => {
                session
                    .command(
                        serde_json::from_value(
                            request.get("command").cloned().ok_or("INVALID_COMMAND")?,
                        )
                        .map_err(err)?,
                    )
                    .await
            }
            "syncObject" => session.sync_object(field(&request, "objectId")?).await,
            "realtimeObject" => session.realtime_object(field(&request, "objectId")?).await,
            "applyUpdate" => {
                session
                    .merge(
                        field(&request, "objectId")?,
                        &B64.decode(field(&request, "update")?).map_err(err)?,
                    )
                    .await
            }
            "applySync" => {
                let bytes = B64.decode(field(&request, "body")?).map_err(err)?;
                let bytes = muse_appflowy_wire::full_sync_response(&bytes, session::LIMIT)?;
                session.merge(field(&request, "objectId")?, &bytes).await
            }
            "undo" => session.history(false).await,
            "redo" => session.history(true).await,
            _ => Err("UNSUPPORTED_ACTION".into()),
        }
    })
}
pub fn call_json(input: &str) -> String {
    let result = if input.len() > 32 * 1024 * 1024 {
        Err("QUOTA_EXCEEDED".into())
    } else {
        serde_json::from_str(input).map_err(err).and_then(execute)
    };
    match result {
        Ok(data) => json!({"ok":true,"data":data}).to_string(),
        Err(error) => json!({"ok":false,"error":error}).to_string(),
    }
}
#[cfg(target_arch = "wasm32")]
#[wasm_bindgen::prelude::wasm_bindgen]
pub fn muse_dataset_core_call_json(input: &str) -> String {
    call_json(input)
}
#[cfg(not(target_arch = "wasm32"))]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn muse_dataset_core_call(
    input: *const std::ffi::c_char,
) -> *mut std::ffi::c_char {
    let response = if input.is_null() {
        json!({"ok":false,"error":"INVALID_INPUT"}).to_string()
    } else {
        match unsafe { std::ffi::CStr::from_ptr(input) }.to_str() {
            Ok(value) => call_json(value),
            Err(_) => json!({"ok":false,"error":"INVALID_UTF8"}).to_string(),
        }
    };
    std::ffi::CString::new(response).unwrap().into_raw()
}
#[cfg(not(target_arch = "wasm32"))]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn muse_dataset_core_free(output: *mut std::ffi::c_char) {
    if !output.is_null() {
        drop(unsafe { std::ffi::CString::from_raw(output) });
    }
}

#[cfg(test)]
mod date_tests;
#[cfg(test)]
mod tests;
