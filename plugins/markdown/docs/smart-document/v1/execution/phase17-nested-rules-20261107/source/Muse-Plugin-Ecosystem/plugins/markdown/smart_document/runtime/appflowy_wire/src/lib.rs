//! Content-independent adapter for the existing AppFlowy full-sync protocol.
//! Encoding is Yrs update-v1, not an algorithm-neutral universal merge format.
//! Successful HTTP exchange is acceptance, never a durable-write receipt.
use prost::Message;
use std::io::Read;

// Wire-identical to Muse-Server/AppFlowy-Cloud/libs/collab-rt-entity/proto/collab.proto.
// This moves the existing smart-document wire adapter; no new protocol is defined.
#[derive(Clone, PartialEq, Message)]
struct FullSync {
    #[prost(string, tag = "1")]
    object_id: String,
    #[prost(int32, tag = "2")]
    collab_type: i32,
    #[prost(int32, tag = "3")]
    compression: i32,
    #[prost(bytes = "vec", tag = "4")]
    sv: Vec<u8>,
    #[prost(bytes = "vec", tag = "5")]
    doc_state: Vec<u8>,
}

pub fn full_sync_request(
    object_id: &str,
    collab_type: i32,
    sv: &[u8],
    state: &[u8],
    limit: usize,
) -> Result<Vec<u8>, String> {
    if object_id.is_empty() || object_id.len() > 128 || !(0..=6).contains(&collab_type) {
        return Err("INVALID_COLLAB_ADDRESS".into());
    }
    if state.len().saturating_add(sv.len()) > limit {
        return Err("QUOTA_EXCEEDED".into());
    }
    Ok(FullSync {
        object_id: object_id.into(),
        collab_type,
        compression: 0,
        sv: sv.to_vec(),
        doc_state: state.to_vec(),
    }
    .encode_to_vec())
}

pub fn full_sync_response(bytes: &[u8], limit: usize) -> Result<Vec<u8>, String> {
    if bytes.len() > limit || limit == 0 {
        return Err("QUOTA_EXCEEDED".into());
    }
    let mut decoded = Vec::new();
    ruzstd::decoding::StreamingDecoder::new_with_max_window_size(bytes, limit as u64)
        .map_err(|e| e.to_string())?
        .take(limit.saturating_add(1) as u64)
        .read_to_end(&mut decoded)
        .map_err(|e| e.to_string())?;
    if decoded.len() > limit {
        return Err("QUOTA_EXCEEDED".into());
    }
    Ok(decoded)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn original_wire_discriminators_and_opaque_payloads_are_preserved() {
        for ty in [0, 1, 4] {
            let raw = full_sync_request("object", ty, &[1, 2], &[3, 4], 100).unwrap();
            let msg = FullSync::decode(raw.as_slice()).unwrap();
            assert_eq!(msg.object_id, "object");
            assert_eq!(msg.collab_type, ty);
            assert_eq!(msg.compression, 0);
            assert_eq!(msg.sv, [1, 2]);
            assert_eq!(msg.doc_state, [3, 4]);
        }
    }
    #[test]
    fn real_server_compression_is_bounded_and_malformed_frames_are_rejected() {
        let raw = vec![42u8; 100];
        let compressed = zstd::encode_all(raw.as_slice(), 0).unwrap();
        assert_eq!(
            full_sync_response(&compressed, 8 * 1024 * 1024).unwrap(),
            raw
        );
        assert!(full_sync_response(&[1, 2, 3], 4096).is_err());
        let large = zstd::encode_all(vec![42u8; 9 * 1024 * 1024].as_slice(), 0).unwrap();
        assert!(full_sync_response(&large, 4096).is_err());
        assert_eq!(
            full_sync_response(&large, 8 * 1024 * 1024).unwrap_err(),
            "QUOTA_EXCEEDED"
        );
        assert!(full_sync_request("object", 4, &[], &[1; 101], 100).is_err());
    }
}
