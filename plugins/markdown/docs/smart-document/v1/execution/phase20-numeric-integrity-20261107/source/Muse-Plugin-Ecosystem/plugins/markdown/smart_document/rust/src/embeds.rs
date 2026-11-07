//! AppFlowy's original inline database locator. The document owns only this
//! structural block, never the referenced database's schema, rows or authority.
use crate::{Result, field};
use collab_document::blocks::{Block, DocumentData};
use serde_json::Value;

fn opaque(s: &str, limit: usize) -> bool {
    !s.is_empty()
        && s.len() <= limit
        && !s.chars().any(|c| c <= ' ' || c == '/' || c == '\\')
        && !(s.len() > 1 && s.as_bytes()[1] == b':')
}
fn keys(v: &Value, allowed: &[&str]) -> Result<()> {
    if !v
        .as_object()
        .is_some_and(|m| m.keys().all(|k| allowed.contains(&k.as_str())))
    {
        return Err("INVALID_EMBED_REFERENCE".into());
    }
    Ok(())
}
fn identity(v: &Value) -> Result<()> {
    let names = ["scope", "source", "workspace", "mount", "resource"];
    keys(v, &names)?;
    for k in names {
        if !opaque(field(v, k)?, 1024) {
            return Err("INVALID_EMBED_REFERENCE".into());
        }
    }
    Ok(())
}
fn version(v: &Value) -> Result<()> {
    keys(v, &["revision", "digest"])?;
    let digest = field(v, "digest")?;
    if !opaque(field(v, "revision")?, 1024)
        || digest.len() != 64
        || !digest
            .bytes()
            .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
    {
        return Err("INVALID_EMBED_REFERENCE".into());
    }
    Ok(())
}
pub fn validate(block: &Block, data: &DocumentData) -> Result<()> {
    if block.parent != data.page_id
        || block.external_id.is_some()
        || block.external_type.is_some()
        || data
            .meta
            .children_map
            .get(&block.children)
            .is_some_and(|c| !c.is_empty())
        || !["parent_id", "view_id"].iter().all(|k| {
            block
                .data
                .get(*k)
                .and_then(Value::as_str)
                .is_some_and(|s| opaque(s, 1024))
        })
    {
        return Err("INVALID_DATABASE_EMBED".into());
    }
    // Upstream references without the Muse resolver extension are preserved and
    // rendered as unavailable, never guessed or silently redirected.
    let Some(target) = block.data.get("muse_embed") else {
        return Ok(());
    };
    if serde_json::to_vec(target).map_err(crate::err)?.len() > 8192 {
        return Err("QUOTA_EXCEEDED".into());
    }
    keys(target, &["protocol", "reference", "surface", "selector"])?;
    if field(target, "protocol")? != "openmuse.resource-embed/v1"
        || !opaque(field(target, "surface")?, 1024)
    {
        return Err("INVALID_EMBED_REFERENCE".into());
    }
    let reference = target.get("reference").ok_or("INVALID_EMBED_REFERENCE")?;
    keys(reference, &["protocol", "identity", "version", "retained"])?;
    if field(reference, "protocol")? != "openmuse.resource-reference/v1" {
        return Err("INVALID_EMBED_REFERENCE".into());
    }
    identity(&reference["identity"])?;
    if let Some(v) = reference.get("version") {
        version(v)?;
    }
    if let Some(retained) = reference.get("retained") {
        keys(retained, &["identity", "version"])?;
        identity(&retained["identity"])?;
        version(&retained["version"])?;
        if retained["identity"]["scope"] != reference["identity"]["scope"]
            || retained["version"]["digest"] != reference["version"]["digest"]
        {
            return Err("INVALID_EMBED_REFERENCE".into());
        }
    }
    let selector = target["selector"]
        .as_object()
        .ok_or("INVALID_EMBED_REFERENCE")?;
    if selector.is_empty()
        || selector.len() > 16
        || selector.iter().any(|(k, v)| {
            k.is_empty()
                || k.len() > 256
                || k.chars().any(char::is_control)
                || !v.as_str().is_some_and(|s| {
                    !s.is_empty() && s.len() <= 2048 && !s.chars().any(char::is_control)
                })
        })
        || target["selector"]["viewId"] != block.data["view_id"]
    {
        return Err("INVALID_EMBED_REFERENCE".into());
    }
    Ok(())
}
