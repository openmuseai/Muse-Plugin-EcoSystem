//! Qualification only: use real upstream Database/Field/View/Row types and CRDT
//! objects before choosing a cross-platform runtime. Not a database UI or release.
use std::sync::Arc;
use async_trait::async_trait;
use collab::{entity::EncodedCollab,lock::RwLock};
use collab_database::{database::{Database,DatabaseContext}, database_trait::{DatabaseCollabReader,EncodeCollabByOid}, error::DatabaseError,
  entity::{CreateDatabaseParams,CreateViewParams,FieldType}, fields::Field, rows::{DatabaseRow,RowId,CreateRowParams}, views::{DatabaseLayout,OrderObjectPosition}};
use collab_entity::CollabType;
use dashmap::DashMap;
use serde_json::json;
struct Reader{rows:Arc<DashMap<RowId,Arc<RwLock<DatabaseRow>>>>}
#[async_trait]
impl DatabaseCollabReader for Reader{
 async fn reader_client_id(&self)->u64{42}
 async fn reader_get_collab(&self,_:&str,_:CollabType)->Result<EncodedCollab,DatabaseError>{Err(DatabaseError::Internal(anyhow_missing().into()))}
 async fn reader_batch_get_collabs(&self,_:Vec<String>,_:CollabType)->Result<EncodeCollabByOid,DatabaseError>{Ok(Default::default())}
 fn database_row_cache(&self)->Option<Arc<DashMap<RowId,Arc<RwLock<DatabaseRow>>>>>{Some(self.rows.clone())}
}
fn anyhow_missing()->std::io::Error{std::io::Error::new(std::io::ErrorKind::NotFound,"Probe has no external data provider")}
#[cfg_attr(target_arch="wasm32",wasm_bindgen::prelude::wasm_bindgen)]
pub fn qualify_database_runtime()->String{
 #[cfg(not(target_arch="wasm32"))]
 let runtime=tokio::runtime::Builder::new_current_thread().build().unwrap();
 let future=async {
  let reader=Arc::new(Reader{rows:Arc::new(DashMap::new())});
  let context=DatabaseContext::new(reader.clone(),reader.clone());
  let database_id=uuid::Uuid::new_v4().to_string();let view_id=uuid::Uuid::new_v4().to_string();
  let fields=vec![Field::from_field_type("标题",FieldType::RichText,true),Field::from_field_type("完成",FieldType::Checkbox,false),Field::from_field_type("链接",FieldType::URL,false)];
  let mut database=Database::create(context,CreateDatabaseParams{database_id:database_id.clone(),fields,
    views:vec![CreateViewParams::new(database_id.clone(),view_id.clone(),"原生 Grid".into(),DatabaseLayout::Grid)],rows:vec![]}).await.unwrap();
  let row_id=uuid::Uuid::new_v4().to_string();
  database.create_row(CreateRowParams{id:row_id.clone().into(),database_id:database_id.clone(),cells:Default::default(),height:36,visibility:true,row_position:OrderObjectPosition::End,created_at:0,modified_at:0}).await.unwrap();
  let loaded=database.get_row(&RowId::from(row_id.clone())).await;
  assert_eq!(loaded.id,RowId::from(row_id.clone()));
  let row=reader.rows.get(&RowId::from(row_id.clone())).unwrap();
  let encoded=row.read().await.collab.encode_collab_v1(|_|Ok::<_,DatabaseError>(())).unwrap();
  json!({"databaseId":database.get_database_id(),"viewCount":database.get_all_views().len(),"fieldCount":database.get_fields(None).len(),
    "rowCount":database.get_row_orders_for_view(&view_id).len(),"rowObjectId":row_id,"independentRowStateBytes":encoded.doc_state.len()}).to_string()
 };
 #[cfg(not(target_arch="wasm32"))]
 {runtime.block_on(future)}
 #[cfg(target_arch="wasm32")]
 {futures::executor::block_on(future)}
}
#[cfg(test)]mod tests{
 #[test]fn upstream_database_and_row_are_independent_objects(){
  let output=super::qualify_database_runtime();let value:serde_json::Value=serde_json::from_str(&output).unwrap();
  assert_eq!(value["fieldCount"],3);assert_eq!(value["viewCount"],1);assert_eq!(value["rowCount"],1);
  assert_ne!(value["databaseId"],value["rowObjectId"]);assert!(value["independentRowStateBytes"].as_u64().unwrap()>0);
 }
}
