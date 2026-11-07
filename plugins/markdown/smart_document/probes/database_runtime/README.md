# Original database runtime qualification

Pinned AppFlowy-Collab e59260e524f33104b0ddcd6bb8f6218cad0f7e18 / collab-database 0.2.0. Reuses upstream Database, Field, View, DatabaseRow and original CRDT state; does not implement an alternative database. Probe creates three fields, one Grid view and an independently encoded row, and fetches the row through the upstream API. Native and real browser WASM paths were exercised.

This is not the product Dataset adapter, a database UI, full field/view support, CSV import certification or Cloud row collaboration acceptance. It is not linked into smart-document's production core.

Run `python3 scripts/verify_database_probe.py --runtime` from smart_document. For browser qualification, use pinned wasm-bindgen 0.2.128 with `--target no-modules --no-modules-global muse_database_probe --no-typescript`; serve the outputs over loopback and call `qualify_database_runtime()` from a user button. Preserve the actual returned shape, screenshot and binary hashes.

The vendor contains the original 74 Rust source files, original manifest and license, original per-file hashes and six explicit adaptations: standalone runtime manifest/native fs feature, foreground browser row loading without an implicit Tokio runtime, inline browser template preparation, sequential browser Rayon paths, and virtual CSV resource delegation to injected FileUrlBuilder. Native scheduling remains as upstream. Do not edit Cargo caches or format the vendor wholesale.

The browser FileUrlBuilder must resolve only its authorized virtual file collection; it does not receive filesystem authority. No browser CSV asset provider is supplied here. Background `init_database_row`/prefetch entry points still require a scheduler adapter; do not expose them merely because this foreground path passes. CSV/template behavior and all field semantics need their own fixtures.
