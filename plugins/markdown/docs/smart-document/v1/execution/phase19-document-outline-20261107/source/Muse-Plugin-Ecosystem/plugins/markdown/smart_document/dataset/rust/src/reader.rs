//! Capability-free in-memory adapter for upstream Database/DatabaseRow services.
//! Network/storage live in the owning client. Missing rows are never fabricated.
use async_trait::async_trait;
use collab::{entity::EncodedCollab, lock::RwLock};
use collab_database::{
    database_trait::{DatabaseCollabReader, EncodeCollabByOid},
    error::DatabaseError,
    rows::{DatabaseRow, RowId},
};
use collab_entity::CollabType;
use dashmap::DashMap;
use std::{
    collections::HashMap,
    sync::{Arc, Mutex},
};

pub struct Reader {
    pub client_id: u64,
    pub encoded: Mutex<HashMap<String, EncodedCollab>>,
    pub rows: Arc<DashMap<RowId, Arc<RwLock<DatabaseRow>>>>,
}
impl Reader {
    pub fn new(client_id: u64) -> Self {
        Self {
            client_id,
            encoded: Mutex::new(HashMap::new()),
            rows: Arc::new(DashMap::new()),
        }
    }
}
#[async_trait]
impl DatabaseCollabReader for Reader {
    async fn reader_client_id(&self) -> u64 {
        self.client_id
    }
    async fn reader_get_collab(
        &self,
        id: &str,
        _: CollabType,
    ) -> Result<EncodedCollab, DatabaseError> {
        self.encoded
            .lock()
            .unwrap()
            .get(id)
            .cloned()
            .ok_or_else(|| {
                DatabaseError::Internal(
                    std::io::Error::new(std::io::ErrorKind::NotFound, "ROW_STATE_REQUIRED").into(),
                )
            })
    }
    async fn reader_batch_get_collabs(
        &self,
        ids: Vec<String>,
        _: CollabType,
    ) -> Result<EncodeCollabByOid, DatabaseError> {
        let encoded = self.encoded.lock().unwrap();
        Ok(ids
            .into_iter()
            .filter_map(|id| encoded.get(&id).cloned().map(|value| (id, value)))
            .collect())
    }
    fn database_row_cache(&self) -> Option<Arc<DashMap<RowId, Arc<RwLock<DatabaseRow>>>>> {
        Some(self.rows.clone())
    }
}
