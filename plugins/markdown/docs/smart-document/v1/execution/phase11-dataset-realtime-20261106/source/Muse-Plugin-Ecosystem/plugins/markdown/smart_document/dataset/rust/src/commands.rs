use crate::{Result, Session, choices, model};
use collab::{core::origin::CollabOrigin, preclude::Transact};
use collab_database::{
    fields::Field,
    rows::{CreateRowParams, RowId},
    views::OrderObjectPosition,
};
use serde::Deserialize;
use serde_json::Value;
use std::collections::HashMap;

#[derive(Clone, Deserialize)]
#[serde(tag = "op", rename_all = "camelCase", deny_unknown_fields)]
pub enum Command {
    CreateField {
        id: String,
        name: String,
        #[serde(rename = "semanticType")]
        semantic_type: String,
        #[serde(default)]
        options: Vec<choices::Choice>,
    },
    RenameField {
        #[serde(rename = "fieldId")]
        field_id: String,
        name: String,
        #[serde(rename = "expectedName")]
        expected_name: String,
    },
    AddRow {
        #[serde(rename = "rowId")]
        row_id: String,
        #[serde(default)]
        cells: HashMap<String, Value>,
    },
    SetCell {
        #[serde(rename = "rowId")]
        row_id: String,
        #[serde(rename = "fieldId")]
        field_id: String,
        value: Value,
        #[serde(rename = "expectedHash")]
        expected_hash: String,
        #[serde(rename = "expectedFieldHash", default)]
        expected_field_hash: Option<String>,
    },
}
impl Session {
    pub async fn apply_command(&mut self, command: &Command) -> Result<()> {
        match command {
            Command::CreateField {
                id,
                name,
                semantic_type,
                options,
            } => {
                model::address(id)?;
                model::name(name)?;
                if self.database.get_fields(None).iter().any(|f| &f.id == id) {
                    return Err("DUPLICATE_FIELD".into());
                }
                let mut field =
                    Field::from_field_type(name, model::field_type(semantic_type)?, false);
                field.id = id.clone();
                let field = choices::configure(field, options)?;
                self.database
                    .create_field(None, field, &OrderObjectPosition::End, HashMap::new());
                self.history_object = self.object_id.clone();
            }
            Command::RenameField {
                field_id,
                name,
                expected_name,
            } => {
                model::name(name)?;
                let field = self
                    .database
                    .get_fields(None)
                    .into_iter()
                    .find(|f| &f.id == field_id)
                    .ok_or("FIELD_MISSING")?;
                if &field.name != expected_name {
                    return Err("FIELD_CHANGED".into());
                }
                self.database.update_field(field_id, |update| {
                    update.set_name(name);
                });
                self.history_object = self.object_id.clone();
            }
            Command::AddRow { row_id, cells } => {
                uuid::Uuid::parse_str(row_id).map_err(|_| "INVALID_ROW_ID")?;
                if self.reader.rows.contains_key(&RowId::from(row_id.clone())) {
                    return Err("DUPLICATE_ROW".into());
                }
                let fields = self.database.get_fields(None);
                let mut values = HashMap::new();
                for (id, value) in cells {
                    let field = fields.iter().find(|f| &f.id == id).ok_or("FIELD_MISSING")?;
                    values.insert(id.clone(), model::write(field, value.clone())?);
                }
                let params =
                    CreateRowParams::new(RowId::from(row_id.clone()), self.object_id.clone())
                        .with_cells(values);
                self.database
                    .create_row(params)
                    .await
                    .map_err(|e| e.to_string())?;
                if let Some(row) = self.reader.rows.get(&RowId::from(row_id.clone())) {
                    row.write().await.collab.enable_undo_redo();
                }
                self.history_object = self.object_id.clone();
            }
            Command::SetCell {
                row_id,
                field_id,
                value,
                expected_hash,
                expected_field_hash,
            } => {
                if !self.row_ids().contains(row_id) {
                    return Err("ROW_NOT_REFERENCED".into());
                }
                let fields = self.database.get_fields(None);
                let field = fields
                    .iter()
                    .find(|f| &f.id == field_id)
                    .ok_or("FIELD_MISSING")?;
                if expected_field_hash
                    .as_ref()
                    .is_some_and(|hash| hash != &model::field_hash(field))
                    || (choices::is_choice(field) && expected_field_hash.is_none())
                {
                    return Err("FIELD_CHANGED".into());
                }
                let row = self
                    .reader
                    .rows
                    .get(&RowId::from(row_id.clone()))
                    .ok_or("ROW_STATE_REQUIRED")?
                    .clone();
                let mut row = row.write().await;
                if model::hash(row.get_cell(field_id).as_ref()) != *expected_hash {
                    return Err("CELL_CHANGED".into());
                }
                let cell = model::write(field, value.clone())?;
                if row.get_cell(field_id).is_none() {
                    // Upstream creates a nested Y.Map on the first write. If
                    // that creation is part of the user's undo frame, undoing
                    // it deletes causally later peer values inside the map.
                    // Prepare only the empty structural container through the
                    // original API, with the already untracked server origin.
                    // User data remains a separate normal origin transaction.
                    let mut txn = row.collab.doc().transact_mut_with(CollabOrigin::Server);
                    row.body.update_cells(&mut txn, |cells| {
                        cells.insert_cell(field_id, HashMap::new());
                    });
                }
                row.collab
                    .undo_manager_mut()
                    .map_err(|e| e.to_string())?
                    .reset();
                row.update(|update| {
                    update.update_cells(|cells| {
                        cells.insert_cell(field_id, cell);
                    });
                });
                row.collab
                    .undo_manager_mut()
                    .map_err(|e| e.to_string())?
                    .reset();
                self.history_object = row_id.clone();
            }
        }
        Ok(())
    }
}
