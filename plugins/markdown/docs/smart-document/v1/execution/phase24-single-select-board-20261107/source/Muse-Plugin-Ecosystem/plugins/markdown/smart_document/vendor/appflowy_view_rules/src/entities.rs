// PB-free data shapes extracted from the pinned original enums; numeric values unchanged.
#[derive(Eq, PartialEq, Debug, Default, Clone)]
pub struct TextFilterPB {
  pub condition: TextFilterConditionPB,
  pub content: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
#[repr(u8)]
pub enum TextFilterConditionPB {
  #[default]
  TextIs = 0,
  TextIsNot = 1,
  TextContains = 2,
  TextDoesNotContain = 3,
  TextStartsWith = 4,
  TextEndsWith = 5,
  TextIsEmpty = 6,
  TextIsNotEmpty = 7,
}

#[derive(Eq, PartialEq, Debug, Default, Clone)]
pub struct NumberFilterPB {
  pub condition: NumberFilterConditionPB,
  pub content: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
#[repr(u8)]
pub enum NumberFilterConditionPB {
  #[default]
  Equal = 0,
  NotEqual = 1,
  GreaterThan = 2,
  LessThan = 3,
  GreaterThanOrEqualTo = 4,
  LessThanOrEqualTo = 5,
  NumberIsEmpty = 6,
  NumberIsNotEmpty = 7,
}

#[derive(Eq, PartialEq, Debug, Default, Clone)]
pub struct SelectOptionFilterPB {
  pub condition: SelectOptionFilterConditionPB,
  pub option_ids: Vec<String>,
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
#[repr(u8)]
pub enum SelectOptionFilterConditionPB {
  #[default]
  OptionIs = 0,
  OptionIsNot = 1,
  OptionContains = 2,
  OptionDoesNotContain = 3,
  OptionIsEmpty = 4,
  OptionIsNotEmpty = 5,
}

pub use crate::date_entities::{DateFilterConditionPB,DateFilterContent,DateFilterPB};
