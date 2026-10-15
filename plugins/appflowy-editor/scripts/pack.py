"""Produce a deterministic MCP Bundle from the standalone editor MCP server."""
import argparse
import hashlib
import json
import subprocess
import zipfile
from pathlib import Path
from urllib.parse import urlparse

root = Path(__file__).resolve().parents[1]
version = "0.1.0"
parser = argparse.ArgumentParser()
parser.add_argument("--editor-url", help="Public HTTPS editor URL to embed in the Desktop MCPB")
parser.add_argument("--out", type=Path, default=root / "dist")
args = parser.parse_args()
out = args.out.resolve()
out.mkdir(parents=True, exist_ok=True)
if args.editor_url:
    parsed = urlparse(args.editor_url)
    if parsed.scheme != "https" and not (parsed.scheme == "http" and parsed.hostname in {"localhost", "127.0.0.1"}):
        parser.error("Editor URL requires HTTPS or loopback HTTP")
    subprocess.run([
        str(root / "node_modules/.bin/esbuild"), "src/mcp_server.ts", "--bundle",
        "--platform=node", "--format=esm", "--target=node22",
        f"--outfile={root / 'dist/server.mjs'}",
        f"--define:process.env.EDITOR_PUBLIC_URL={json.dumps(args.editor_url)}",
    ], cwd=root, check=True)
manifest = {
    "manifest_version": "0.3",
    "name": "appflowy-editor",
    "display_name": "AppFlowy Editor",
    "version": version,
    "description": "Rich text editor based on AppFlowy Editor; delivered as an MCP App.",
    "author": {"name": "OpenMuse contributors"},
    "license": "MPL-2.0",
    "repository": {"type": "git", "url": "https://github.com/AppFlowy-IO/appflowy-editor"},
    "tools": [{"name": "open_editor", "description": "Open the rich text editor"}],
    "compatibility": {"platforms": ["darwin", "win32", "linux"], "runtimes": {"node": ">=22.0.0"}},
    "server": {"type": "node", "entry_point": "server/index.mjs", "mcp_config": {"command": "node", "args": ["${__dirname}/server/index.mjs"]}},
}
entries = {
    "manifest.json": (json.dumps(manifest, separators=(",", ":")) + "\n").encode(),
    "server/index.mjs": (root / "dist/server.mjs").read_bytes(),
    "LICENSE": (root / "vendor/appflowy_editor/LICENSE").read_bytes(),
}
package = out / f"appflowy-editor-{version}.mcpb"
with zipfile.ZipFile(package, "w", compression=zipfile.ZIP_DEFLATED) as archive:
    for name, data in sorted(entries.items()):
        info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        archive.writestr(info, data)
digest = hashlib.sha256(package.read_bytes()).hexdigest()
(out / "mcpb.sha256").write_text(f"{digest}  {package.name}\n")
print(package)
