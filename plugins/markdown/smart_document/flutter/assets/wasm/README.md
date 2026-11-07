# Generated browser core

Run `python3 scripts/build_web_core.py` from `smart_document` before building Web.
The pinned Rust source and wasm-bindgen 0.2.128 generate the `.js` and `.wasm`
assets here. Generated binaries are ignored by git; hashes are recorded in
`.build/wasm-artifacts.json`. The application does not download executable code
from a third-party CDN.
