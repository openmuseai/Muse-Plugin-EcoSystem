#!/usr/bin/env python3
"""Build the same AppFlowy domain core for browsers, with a pinned binding tool."""
import hashlib
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
VERSION = '0.2.128'


def main():
    actual = subprocess.check_output(['wasm-bindgen', '--version'], text=True).strip()
    if actual != 'wasm-bindgen ' + VERSION:
        raise SystemExit('Install wasm-bindgen-cli ' + VERSION + ' with cargo install --locked --version ' + VERSION + ' wasm-bindgen-cli')
    subprocess.run(['cargo', 'build', '--locked', '--release', '--target', 'wasm32-unknown-unknown',
                    '--manifest-path', str(ROOT / 'rust/Cargo.toml')], check=True)
    assets = ROOT / 'flutter/assets/wasm'
    assets.mkdir(parents=True, exist_ok=True)
    subprocess.run(['wasm-bindgen', '--target', 'no-modules', '--no-modules-global', 'muse_smart_document_wasm',
                    '--no-typescript', '--out-dir', str(assets),
                    str(ROOT / 'rust/target/wasm32-unknown-unknown/release/muse_smart_document.wasm')], check=True)
    # no-modules declares a lexical `let`; Dart interop reads a global property.
    glue = assets / 'muse_smart_document.js'
    glue.write_text(glue.read_text() + '\nglobalThis.muse_smart_document_wasm = muse_smart_document_wasm;\n')
    report = {'collabRevision': 'e59260e524f33104b0ddcd6bb8f6218cad0f7e18', 'bindgenVersion': VERSION,
              'artifacts': [{'file': p.name, 'bytes': p.stat().st_size,
                             'sha256': hashlib.sha256(p.read_bytes()).hexdigest()}
                            for p in sorted(assets.glob('muse_smart_document*'))]}
    (ROOT / '.build').mkdir(exist_ok=True)
    (ROOT / '.build/wasm-artifacts.json').write_text(json.dumps(report, indent=2) + '\n')
    print('WASM core and JavaScript loader built and hashed')


if __name__ == '__main__':
    main()
