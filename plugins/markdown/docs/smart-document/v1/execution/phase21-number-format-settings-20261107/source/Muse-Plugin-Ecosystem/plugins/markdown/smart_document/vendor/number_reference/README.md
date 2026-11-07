# Pinned numeric editing references

Read-only original SiYuan and AppFlowy sources, not compiled into another kernel. SiYuan separates content/isNotEmpty/format/formattedContent and uses the unformatted content in the numeric editor. The running adapter reuses the already pinned collab-database NumberCellData, NumberTypeOption and type-option reader/writer, plus its existing Decimal dependency.

Controlled adaptation: exact decimal strings instead of JS double, whole-literal validation instead of partial extraction, unresolved legacy values remain encoded and readonly. Unchanged dialog apply does not call a content command. Original number-format metadata can be configured by the SDK adapter; a complete SiYuan format UI and percent/locale semantics are not claimed. Licenses are retained with both original source groups.
