//! Original filter seed decisions, using original collab-database cell writers.
use collab_database::{entity::FieldType, fields::{Field,type_option_cell_writer,select_type_option::{SelectOption, SelectTypeOption}},rows::Cell};
use serde_json::json;
pub trait PreFillCellsWithFilter { fn get_compliant_cell(&self,field:&Field)->Option<Cell>; }
pub fn insert_text_cell(value:String,field:&Field)->Cell {
 let ty=FieldType::from(field.field_type);
 type_option_cell_writer(field.get_any_type_option(field.field_type).unwrap_or_default(),&ty).convert_json_to_cell(json!(value))
}
pub fn insert_select_option_cell(ids:Vec<String>,field:&Field)->Cell {
 let ty=FieldType::from(field.field_type);
 type_option_cell_writer(field.get_any_type_option(field.field_type).unwrap_or_default(),&ty).convert_json_to_cell(json!(ids.into_iter().map(|id|json!({"id":id})).collect::<Vec<_>>()))
}
pub struct SelectOptions(SelectTypeOption);
impl SelectOptions {pub fn mut_options(&mut self)->&mut Vec<SelectOption>{&mut self.0.options}}
pub fn select_type_option_from_field(field:&Field)->Result<SelectOptions,()> {
 if !matches!(field.field_type,3|4) {return Err(());}
 Ok(SelectOptions(SelectTypeOption::from(field.get_any_type_option(field.field_type).unwrap_or_default())))
}

pub fn insert_date_cell(timestamp:i64,end_timestamp:Option<i64>,include_time:Option<bool>,_field:&Field)->Cell {
    Cell::from(&collab_database::fields::date_type_option::DateCellData {timestamp:Some(timestamp),end_timestamp,include_time:include_time.unwrap_or(false),..Default::default()})
}
