#!/usr/bin/env python3
"""Check runtime qualification provenance; never certifies database product parity."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--runtime',action='store_true',help='Also run native probe and build WASM; browser action is separate')
    args=parser.parse_args()
    counts=[]
    for vendor in [ROOT/'probes/database_runtime/vendor/collab-database', ROOT/'vendor/appflowy_database']:
        metadata=json.loads((vendor/'openmuse-upstream.json').read_text())
        expected=json.loads((vendor/'upstream-files.json').read_text())
        assert metadata['revision']=='e59260e524f33104b0ddcd6bb8f6218cad0f7e18'
        for patch in metadata['patches']:expected[patch['file']]=patch['sha256']
        for name,digest in expected.items():
                path=vendor/name
                assert path.resolve().is_relative_to(vendor.resolve()) and not path.is_symlink() and path.is_file(),name
                assert hashlib.sha256(path.read_bytes()).hexdigest()==digest,name
        assert hashlib.sha256((vendor/'openmuse.patch').read_bytes()).hexdigest()==metadata['patchSha256']
        actual={str(p.relative_to(vendor)) for p in vendor.rglob('*') if p.is_file()}-{'upstream-files.json','openmuse-upstream.json','openmuse.patch'}
        assert actual==set(expected),'Unlisted runtime source'
        counts.append((len(expected),len(metadata['patches'])))
    assert counts[0]==counts[1]
    if args.runtime:
        for command in [['test'],['build','--release','--target','wasm32-unknown-unknown']]:
            subprocess.run(['cargo',*command,'--locked','--offline','--manifest-path',str(ROOT/'probes/database_runtime/Cargo.toml')],check=True)
    print(f'Original database runtime: {len(expected)} files, {len(metadata["patches"])} controlled adaptations; product database parity NOT CERTIFIED')
if __name__=='__main__':main()
