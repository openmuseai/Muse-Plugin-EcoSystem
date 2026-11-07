use crate::{
    Result,
    commands::Command,
    err,
    model::{self, Bundle, ObjectState},
    reader::Reader,
};
use base64::{Engine, engine::general_purpose::STANDARD as B64};
use collab::{
    core::{
        collab::{Collab, CollabOptions, DataSource, default_client_id},
        origin::CollabOrigin,
    },
    entity::EncodedCollab,
    preclude::{
        Doc, Options, ReadTxn, StateVector, Transact, Update,
        updates::{decoder::Decode, encoder::Encode},
    },
};
use collab_database::{
    database::{Database, DatabaseContext},
    database_trait::DatabaseRowCollabService,
    entity::{CreateDatabaseParams, CreateViewParams, FieldType},
    fields::Field,
    rows::RowId,
    views::DatabaseLayout,
};
use collab_entity::CollabType;
use serde_json::{Value, json};
use std::{collections::HashSet, sync::Arc};

pub const LIMIT: usize = 8 * 1024 * 1024;
const TOTAL: usize = 16 * 1024 * 1024;
pub struct Session {
    pub object_id: String,
    pub database: Database,
    pub reader: Arc<Reader>,
    pub revision: u64,
    pub history_object: String,
    undo_frames: Vec<String>,
    redo_frames: Vec<String>,
}
fn encoded(id: &str, kind: CollabType, raw: Vec<u8>, client: u64) -> Result<EncodedCollab> {
    if raw.len() > LIMIT {
        return Err("QUOTA_EXCEEDED".into());
    }
    let collab = Collab::new_with_options(
        CollabOrigin::Empty,
        CollabOptions::new(id.to_string(), client).with_data_source(DataSource::DocStateV1(raw)),
    )
    .map_err(err)?;
    kind.validate_require_data(&collab).map_err(err)?;
    collab
        .encode_collab_v1(|c| kind.validate_require_data(c))
        .map_err(err)
}
impl Session {
    pub async fn open(id: &str, bundle: Option<Bundle>, client: Option<u64>) -> Result<Self> {
        let uuid = uuid::Uuid::parse_str(id).map_err(|_| "INVALID_DATASET_ID")?;
        let reader = Arc::new(Reader::new(client.unwrap_or_else(default_client_id)));
        let context = DatabaseContext::new(reader.clone(), reader.clone());
        let mut row_objects = vec![];
        let mut root = None;
        if let Some(bundle) = bundle {
            if bundle.profile != "muse.dataset.bundle/0.1"
                || bundle.object_id != id
                || bundle.objects.len() > 1001
            {
                return Err("INVALID_BUNDLE".into());
            }
            let mut unique = HashSet::new();
            let mut total = 0;
            for object in bundle.objects {
                if !unique.insert(object.object_id.clone()) {
                    return Err("DUPLICATE_OBJECT".into());
                }
                let bytes = B64.decode(&object.doc_state).map_err(err)?;
                total += bytes.len();
                if total > TOTAL {
                    return Err("QUOTA_EXCEEDED".into());
                }
                let kind = if object.object_id == id && object.collab_type == 1 {
                    CollabType::Database
                } else if object.object_id != id && object.collab_type == 4 {
                    uuid::Uuid::parse_str(&object.object_id).map_err(|_| "INVALID_ROW_ID")?;
                    CollabType::DatabaseRow
                } else {
                    return Err("INVALID_OBJECT_TYPE".into());
                };
                let value = encoded(&object.object_id, kind, bytes, reader.client_id)?;
                reader
                    .encoded
                    .lock()
                    .unwrap()
                    .insert(object.object_id.clone(), value);
                if kind == CollabType::Database {
                    root = Some(object.object_id);
                } else {
                    row_objects.push(object.object_id);
                }
            }
            if root.is_none() {
                return Err("ROOT_STATE_REQUIRED".into());
            }
        }
        let mut database = if root.is_some() {
            Database::open(id, context).await.map_err(err)?
        } else {
            let fields = [
                ("title", "标题", FieldType::RichText, true),
                ("done", "完成", FieldType::Checkbox, false),
                ("url", "链接", FieldType::URL, false),
            ]
            .into_iter()
            .map(|(id, name, ty, primary)| {
                let mut field = Field::from_field_type(name, ty, primary);
                field.id = id.into();
                field
            })
            .collect();
            Database::create(
                context,
                CreateDatabaseParams {
                    database_id: id.into(),
                    fields,
                    rows: vec![],
                    views: vec![CreateViewParams::new(
                        id.into(),
                        uuid::Uuid::new_v5(&uuid, b"default-grid").to_string(),
                        "表格".into(),
                        DatabaseLayout::Grid,
                    )],
                },
            )
            .await
            .map_err(err)?
        };
        database.collab.enable_undo_redo();
        for id in row_objects {
            let row = reader
                .build_arc_database_row(&id, None, None)
                .await
                .map_err(err)?;
            row.write().await.collab.enable_undo_redo();
        }
        let s = Self {
            object_id: id.into(),
            database,
            reader,
            revision: 0,
            history_object: id.into(),
            undo_frames: vec![],
            redo_frames: vec![],
        };
        s.validate().await?;
        Ok(s)
    }
    pub fn row_ids(&self) -> HashSet<String> {
        crate::views::primary(&self.database)
            .map(|v| v.row_orders.into_iter().map(|r| r.id.to_string()).collect())
            .unwrap_or_default()
    }
    pub async fn validate(&self) -> Result<()> {
        self.database.validate().map_err(err)?;
        if self.database.get_database_id() != self.object_id {
            return Err("DATASET_ID_MISMATCH".into());
        }
        let fields = self.database.get_fields(None);
        if fields.len() > 128 || self.reader.rows.len() > 1000 || self.row_ids().len() > 1000 {
            return Err("QUOTA_EXCEEDED".into());
        }
        let field_ids: HashSet<_> = fields.iter().map(|f| f.id.as_str()).collect();
        for field in &fields {
            model::address(&field.id)?;
            model::name(&field.name)?;
        }
        let mut views = self.database.get_all_views();
        let primary = crate::views::primary(&self.database)?;
        if views.is_empty() || views.len() > 32 {
            return Err("INVALID_VIEWS".into());
        }
        views.push(primary);
        for view in views {
            if view.database_id != self.object_id
                || view
                    .field_orders
                    .iter()
                    .any(|f| !field_ids.contains(f.id.as_str()))
            {
                return Err("INVALID_VIEW_REFERENCE".into());
            }
            model::address(&view.id)?;
            let mut unique = HashSet::new();
            for row in view.row_orders {
                uuid::Uuid::parse_str(&row.id).map_err(|_| "INVALID_ROW_ID")?;
                if !unique.insert(row.id) {
                    return Err("DUPLICATE_ROW_ORDER".into());
                }
            }
        }
        for item in self.reader.rows.iter() {
            let row = item.value().read().await;
            row.validate().map_err(err)?;
            let data = row.get_row().ok_or("INVALID_ROW_STATE")?;
            if data.database_id != self.object_id
                || data.id != *item.key()
                || data.cells.len() > 1024
            {
                return Err("ROW_SCOPE_MISMATCH".into());
            }
            for cell in data.cells.values() {
                if serde_json::to_vec(cell).map_err(err)?.len() > 65536 {
                    return Err("QUOTA_EXCEEDED".into());
                }
            }
        }
        Ok(())
    }
    pub async fn bundle(&self) -> Result<Bundle> {
        let mut objects = vec![ObjectState {
            object_id: self.object_id.clone(),
            collab_type: 1,
            doc_state: B64.encode(
                self.database
                    .collab
                    .encode_collab_v1(|c| CollabType::Database.validate_require_data(c))
                    .map_err(err)?
                    .doc_state,
            ),
        }];
        for item in self.reader.rows.iter() {
            let row = item.value().read().await;
            objects.push(ObjectState {
                object_id: item.key().to_string(),
                collab_type: 4,
                doc_state: B64.encode(row.encoded_collab().map_err(err)?.doc_state),
            });
        }
        objects.sort_by(|a, b| a.object_id.cmp(&b.object_id));
        let bundle = Bundle {
            profile: "muse.dataset.bundle/0.1".into(),
            object_id: self.object_id.clone(),
            objects,
        };
        if serde_json::to_vec(&bundle).map_err(err)?.len() > TOTAL {
            return Err("QUOTA_EXCEEDED".into());
        }
        Ok(bundle)
    }
    pub async fn read_row(&self, view_id: &str, row_id: &str) -> Result<Value> {
        let view = self
            .database
            .get_all_views()
            .into_iter()
            .find(|v| v.id == view_id)
            .ok_or("VIEW_MISSING")?;
        if !crate::views::rows(&self.database, &view)?
            .iter()
            .any(|r| r.id.to_string() == row_id)
        {
            return Err("ROW_NOT_REFERENCED".into());
        }
        let fields = crate::views::fields(&self.database, &view)?;
        self.project_row(row_id, &fields).await
    }
    async fn project_row(
        &self,
        row_id: &str,
        fields: &[collab_database::fields::Field],
    ) -> Result<Value> {
        let row = self
            .reader
            .rows
            .get(&collab_database::rows::RowId::from(row_id.to_string()))
            .ok_or("ROW_STATE_REQUIRED")?
            .clone();
        let row = row.read().await;
        let mut cells = serde_json::Map::new();
        for field in fields {
            let raw_cell = row.get_cell(&field.id);
            let cell = model::logical_cell(raw_cell.as_ref());
            let display = match (model::readers(field), cell) {
                (Some(_), Some(cell)) if field.field_type == 2 => {
                    crate::dates::projection(field, Some(cell))
                }
                (Some((reader, _)), Some(cell)) => reader.json_cell(cell),
                (Some(_), None) => Value::Null,
                _ => model::raw(cell),
            };
            cells.insert(field.id.clone(),json!({"value":display,"hash":model::hash(cell),"selectedOptionIds":crate::choices::selected(field,cell),"unresolvedOptions":crate::choices::unresolved(field,cell),"unresolvedDate":crate::dates::unresolved(field,cell),"numberInput":crate::numbers::input(field,cell),"unresolvedNumber":crate::numbers::unresolved(field,cell),"raw":model::raw(cell)}));
        }

        Ok(json!({"id":row_id,"loaded":true,"cells":cells}))
    }
    pub async fn snapshot(&self) -> Result<Value> {
        let views = self.database.get_all_views();
        let mut rendered_views = vec![];
        let default_id = uuid::Uuid::new_v5(
            &uuid::Uuid::parse_str(&self.object_id).map_err(err)?,
            b"default-grid",
        )
        .to_string();
        let mut views = views;
        views.sort_by(|a, b| {
            (a.id != default_id, a.created_at, &a.id).cmp(&(
                b.id != default_id,
                b.created_at,
                &b.id,
            ))
        });
        for view in &views {
            let fields = crate::views::fields(&self.database, view)?;
            let columns=fields.iter().map(|f|json!({"id":f.id,"name":f.name,"storageType":f.field_type,"semanticType":model::semantic(f),"editable":model::readers(f).is_some(),"fieldHash":model::field_hash(f),"options":crate::choices::projection(f),"dateOptions":crate::dates::field_projection(f),"numberOptions":crate::numbers::options(f).map(|o|json!({"format":o.format.value()})),"raw":f})).collect::<Vec<_>>();
            let mut rows = vec![];
            let effective_rows = crate::views::rows(&self.database, view)?;
            for order in &effective_rows {
                if !self.reader.rows.contains_key(&order.id) {
                    rows.push(json!({"id":order.id,"loaded":false}));
                    continue;
                }
                rows.push(self.project_row(&order.id.to_string(), &fields).await?);
            }
            let row_objects = rows
                .iter()
                .map(|r| json!({"id":r["id"],"loaded":r["loaded"]}))
                .collect::<Vec<_>>();
            let filters = serde_json::to_value(&view.filters).map_err(err)?;
            let sorts = serde_json::to_value(&view.sorts).map_err(err)?;
            let mut projected = rows.clone();
            let rule_result = crate::view_rules::Rules::parse(&filters, &sorts, &fields)
                .and_then(|rules| rules.project(&mut projected, &fields));
            let rules_ready = rule_result.is_ok();
            let rules_error = rule_result.err();
            if rules_ready {
                rows = projected;
            }
            let loaded = rows.iter().filter(|r| r["loaded"] == true).count();
            rendered_views.push(json!({"id":view.id,"name":view.name,"layout":view.layout,"columns":columns,"rows":rows,"raw":view,
                "board":crate::board::projection(view,&fields,&rows),"rowObjects":row_objects,"rulesReady":rules_ready,"rulesError":rules_error,"rulesHash":crate::view_rules::rules_hash(view),"fieldsHash":crate::view_rules::fields_hash(&fields),
                "dateFilterInputs":crate::date_filters::inputs(&filters,&fields),"filters":filters,"sorts":sorts,"totalRows":effective_rows.len(),"matchedRows":loaded,"isDefault":view.id == default_id}));
        }
        let can_undo = match self.undo_frames.last() {
            Some(id) => self.encoded_object(id).await?.1,
            None => false,
        };
        let can_redo = match self.redo_frames.last() {
            Some(id) => self.encoded_object(id).await?.2,
            None => false,
        };
        Ok(
            json!({"profile":"muse.dataset/0.1","objectId":self.object_id,"revision":self.revision,"views":rendered_views,"bundle":self.bundle().await?,
   "historyObjectId":self.history_object,"canUndo":can_undo,"canRedo":can_redo,"capabilities":{"fieldTypes":["text","number","checkbox","url","singleSelect","multiSelect","date"],"layouts":["grid","singleSelectBoard"],"serverDurableAck":false}}),
        )
    }
    async fn encoded_object(&self, id: &str) -> Result<(EncodedCollab, bool, bool)> {
        if id == self.object_id {
            return Ok((
                self.database
                    .collab
                    .encode_collab_v1(|c| CollabType::Database.validate_require_data(c))
                    .map_err(err)?,
                self.database.collab.can_undo(),
                self.database.collab.can_redo(),
            ));
        }
        let row = self
            .reader
            .rows
            .get(&RowId::from(id))
            .ok_or("ROW_STATE_REQUIRED")?
            .clone();
        let row = row.read().await;
        Ok((
            row.encoded_collab().map_err(err)?,
            row.collab.can_undo(),
            row.collab.can_redo(),
        ))
    }
    async fn preflight_budget(&self, next: &Self) -> Result<()> {
        // Reopening a candidate may GC deleted values retained by a live undo
        // manager. Measure the union in a skip-GC scratch Doc instead, so quota
        // validation does not underestimate the live post-command encoding.
        let current = self.bundle().await?;
        let mut proposed = next.bundle().await?;
        for object in &mut proposed.objects {
            let doc = Doc::with_options(Options {
                skip_gc: true,
                ..Options::default()
            });
            if let Some(old) = current
                .objects
                .iter()
                .find(|o| o.object_id == object.object_id)
            {
                doc.transact_mut()
                    .apply_update(
                        Update::decode_v1(&B64.decode(&old.doc_state).map_err(err)?)
                            .map_err(err)?,
                    )
                    .map_err(err)?;
            }
            doc.transact_mut()
                .apply_update(
                    Update::decode_v1(&B64.decode(&object.doc_state).map_err(err)?).map_err(err)?,
                )
                .map_err(err)?;
            let state = doc
                .transact()
                .encode_state_as_update_v1(&StateVector::default());
            if state.len() > LIMIT {
                return Err("QUOTA_EXCEEDED".into());
            }
            object.doc_state = B64.encode(state);
        }
        if serde_json::to_vec(&proposed).map_err(err)?.len() > TOTAL {
            return Err("QUOTA_EXCEEDED".into());
        }
        Ok(())
    }
    pub async fn command(&mut self, command: Command) -> Result<Value> {
        let mut candidate = Self::open(
            &self.object_id,
            Some(self.bundle().await?),
            Some(self.reader.client_id),
        )
        .await?;
        candidate.apply_command(&command).await?;
        candidate.validate().await?;
        self.preflight_budget(&candidate).await?;
        self.database
            .collab
            .undo_manager_mut()
            .map_err(err)?
            .reset();
        let target = candidate.history_object.clone();
        let before = self.encoded_object(&target).await?.0;
        self.apply_command(&command).await?;
        let changed = before != self.encoded_object(&target).await?.0;
        if changed {
            self.undo_frames.push(target);
            self.redo_frames.clear();
        }
        self.database
            .collab
            .undo_manager_mut()
            .map_err(err)?
            .reset();
        self.revision += 1;
        self.snapshot().await
    }
    pub async fn merge(&mut self, id: &str, bytes: &[u8]) -> Result<Value> {
        if bytes.len() > LIMIT {
            return Err("QUOTA_EXCEEDED".into());
        }
        let mut next = Self::open(
            &self.object_id,
            Some(self.bundle().await?),
            Some(self.reader.client_id),
        )
        .await?;
        next.merge_unchecked(id, bytes).await?;
        next.validate().await?;
        self.preflight_budget(&next).await?;
        let before = self.encoded_object(id).await.ok().map(|v| v.0);
        self.merge_unchecked(id, bytes).await?;
        let after = self.encoded_object(id).await?.0;
        let changed = before.as_ref() != Some(&after);
        if changed {
            self.revision += 1;
        }
        let mut state = self.snapshot().await?;
        state["changed"] = json!(changed);
        Ok(state)
    }
    async fn merge_unchecked(&mut self, id: &str, bytes: &[u8]) -> Result<()> {
        let update = Update::decode_v1(bytes).map_err(err)?;
        if id == self.object_id {
            self.database
                .collab
                .doc()
                .transact_mut_with(CollabOrigin::Server)
                .apply_update(update)
                .map_err(err)?;
        } else if let Some(row) = self.reader.rows.get(&RowId::from(id)).map(|r| r.clone()) {
            row.write()
                .await
                .collab
                .doc()
                .transact_mut_with(CollabOrigin::Server)
                .apply_update(update)
                .map_err(err)?;
        } else {
            uuid::Uuid::parse_str(id).map_err(|_| "INVALID_ROW_ID")?;
            let data = encoded(
                id,
                CollabType::DatabaseRow,
                bytes.to_vec(),
                self.reader.client_id,
            )?;
            self.reader.encoded.lock().unwrap().insert(id.into(), data);
            let row = self
                .reader
                .build_arc_database_row(id, None, None)
                .await
                .map_err(err)?;
            row.write().await.collab.enable_undo_redo();
        }
        Ok(())
    }
    pub async fn sync_object(&self, id: &str) -> Result<Value> {
        let (encoded, _, _) = self.encoded_object(id).await?;
        let kind = if id == self.object_id { 1 } else { 4 };
        Ok(
            json!({"objectId":id,"collabType":kind,"stateVector":B64.encode(&encoded.state_vector),"docState":B64.encode(&encoded.doc_state),"encodedCollab":B64.encode(encoded.encode_to_bytes().map_err(err)?),
   "body":B64.encode(muse_appflowy_wire::full_sync_request(id,kind,&encoded.state_vector,&encoded.doc_state,LIMIT)?)}),
        )
    }
    pub async fn realtime_object(&self, id: &str) -> Result<Value> {
        let kind = if id == self.object_id {
            1
        } else if self.row_ids().contains(&id.to_string()) {
            4
        } else {
            return Err("ROW_NOT_REFERENCED".into());
        };
        if kind == 4 && !self.reader.rows.contains_key(&RowId::from(id.to_string())) {
            return Ok(
                json!({"objectId":id,"collabType":kind,"stateVector":B64.encode(StateVector::default().encode_v1()),"loaded":false}),
            );
        }
        let (encoded, _, _) = self.encoded_object(id).await?;
        Ok(
            json!({"objectId":id,"collabType":kind,"stateVector":B64.encode(encoded.state_vector),"docState":B64.encode(encoded.doc_state),"loaded":true}),
        )
    }
    pub async fn history(&mut self, redo: bool) -> Result<Value> {
        // The application timeline chooses an object; its original Yrs manager
        // owns inversion and origin filtering. Remote transactions add no frames.
        let frames = if redo {
            &self.redo_frames
        } else {
            &self.undo_frames
        };
        let Some(target) = frames.last().cloned() else {
            return self.snapshot().await;
        };
        let performed = if target == self.object_id {
            if redo {
                self.database
                    .collab
                    .undo_manager_mut()
                    .map_err(err)?
                    .redo_one_blocking()
            } else {
                self.database
                    .collab
                    .undo_manager_mut()
                    .map_err(err)?
                    .undo_one_blocking()
            }
        } else {
            if !self.row_ids().contains(&target) {
                return Err("ROW_NOT_REFERENCED".into());
            }
            let row = self
                .reader
                .rows
                .get(&RowId::from(target.clone()))
                .ok_or("ROW_STATE_REQUIRED")?
                .clone();
            let mut row = row.write().await;
            if redo {
                row.collab
                    .undo_manager_mut()
                    .map_err(err)?
                    .redo_one_blocking()
            } else {
                row.collab
                    .undo_manager_mut()
                    .map_err(err)?
                    .undo_one_blocking()
            }
        };
        // A peer may have removed the target. Consume an obsolete frame without
        // falling through into any older command, including the same object.
        if redo {
            self.redo_frames.pop();
        } else {
            self.undo_frames.pop();
        }
        if performed {
            if redo {
                self.undo_frames.push(target.clone());
            } else {
                self.redo_frames.push(target.clone());
            }
        }
        self.history_object = target;
        self.validate().await?;
        self.revision += 1;
        let mut snapshot = self.snapshot().await?;
        snapshot["historyApplied"] = json!(performed);
        Ok(snapshot)
    }
}
