//! Lossless UID projection of the original authenticated Cloud profile response.
//! This decoder does not authenticate bytes. The provider owns authenticated
//! origin-bound HTTP and never exposes the remaining private profile fields.
use crate::Result;
use serde_json::{Value, json};
pub fn decode(body: &[u8]) -> Result<Value> {
    if body.len() > 65536 {
        return Err("PROFILE_QUOTA_EXCEEDED".into());
    }
    let value: Value = serde_json::from_slice(body).map_err(|_| "INVALID_PROFILE_IDENTITY")?;
    if value["code"].as_i64() != Some(0) {
        return Err("PROFILE_REJECTED".into());
    }
    let uid = value["data"]["uid"]
        .as_i64()
        .filter(|v| *v > 0)
        .ok_or("INVALID_PROFILE_IDENTITY")?;
    Ok(json!({"uid":uid.to_string()}))
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn original_profile_uid_is_lossless_and_private_fields_do_not_escape() {
        let result=decode(br#"{"code":0,"data":{"uid":9223372036854775807,"email":"synthetic@example.invalid","name":"ignored"}}"#).unwrap();
        assert_eq!(result, json!({"uid":"9223372036854775807"}));
    }
    #[test]
    fn malformed_noncanonical_or_unbounded_profile_identity_is_rejected() {
        for body in [
            r#"{"code":0,"data":{"uid":0}}"#,
            r#"{"code":0,"data":{"uid":-1}}"#,
            r#"{"code":0,"data":{"uid":"42"}}"#,
            r#"{"code":0,"data":{"uid":1.5}}"#,
            r#"{"code":0,"data":{"uid":9223372036854775808}}"#,
            r#"{"code":1,"data":{"uid":42}}"#,
            "{}",
            "null",
            "garbage",
        ] {
            assert!(decode(body.as_bytes()).is_err(), "{body}");
        }
        assert!(decode(&vec![b' '; 65537]).is_err());
    }
}
