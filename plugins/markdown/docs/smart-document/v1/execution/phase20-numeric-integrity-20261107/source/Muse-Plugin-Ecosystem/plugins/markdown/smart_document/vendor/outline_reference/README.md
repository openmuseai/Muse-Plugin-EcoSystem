# Pinned outline references

Read-only reference sources, not a second editor/kernel. AppFlowy supplies original heading traversal and scrolling APIs; SiYuan supplies preceding-lower-heading hierarchy and separate outline expansion semantics. The running content projection calls the already pinned collab-document Document.get_plain_text_from_block, while Flutter uses the existing AppFlowy EditorScrollController.

Controlled adaptations: include empty valid headings, close quote/table/embed/unknown scopes, cap display labels at 256 Unicode scalar values, adjust the original editor list index for this product's header, never place an editing selection during reading navigation. Body folding and focus mode are separate unfinished features.

Original licenses are retained beside their sources. No upstream source in this directory is modified or compiled.
