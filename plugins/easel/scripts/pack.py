"""Build a self-contained, deterministic Easel MCPB application package."""
from __future__ import annotations

import hashlib
import json
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VERSION = json.loads((ROOT / "package.json").read_text())["version"]


def main() -> Path:
    manifest = {
        "manifest_version": "0.3",
        "name": "easel",
        "display_name": "Easel 社媒管理",
        "version": VERSION,
        "description": "本机社交媒体素材加工、账号授权与发布；首次打开自有安装向导准备 Python、Chromium 和 FFmpeg。",
        "author": {"name": "OpenMuse contributors"},
        "license": "Apache-2.0",
        "repository": {"type": "git", "url": "https://github.com/openmuseai/Muse-Plugin-Ecosystem"},
        "tools": [
            {"name": "easel_open", "description": "打开 Easel 安装向导"},
            {"name": "easel_setup_status", "description": "检查本机依赖"},
            {"name": "easel_setup_start", "description": "用户确认后准备本机依赖"},
            {"name": "easel_setup_job", "description": "查看安装进度"},
        ],
        "compatibility": {"platforms": ["darwin"], "runtimes": {"node": ">=22.0.0"}},
        "server": {"type": "node", "entry_point": "server/index.mjs", "mcp_config": {"command": "node", "args": ["${__dirname}/server/index.mjs"]}},
    }
    entries = {
        "manifest.json": (json.dumps(manifest, ensure_ascii=False, separators=(",", ":")) + "\n").encode(),
        "package.json": (json.dumps({"name": "@openmuse/easel-plugin", "version": VERSION, "type": "module", "bin": {"easel": "server/cli.mjs"}}, separators=(",", ":")) + "\n").encode(),
        "server/index.mjs": (ROOT / "dist/server.mjs").read_bytes(),
        "server/cli.mjs": (ROOT / "dist/cli.mjs").read_bytes(),
        "web/index.html": (ROOT / "dist/index.html").read_bytes(),
        "LICENSE": (ROOT / "UPSTREAM-LICENSE").read_bytes(),
        "NOTICE": (ROOT / "UPSTREAM-NOTICE").read_bytes(),
        "third_party_licenses/WJZ-P-AGPL-3.0.txt": (ROOT / "third_party_licenses/WJZ-P-AGPL-3.0.txt").read_bytes(),
    }
    for directory in ("runtime", "shared/scripts"):
        for path in sorted((ROOT / directory).glob("*")):
            if path.is_file() and path.suffix in {".py", ".txt", ".png"}:
                entries[str(path.relative_to(ROOT))] = path.read_bytes()
    package = ROOT / "dist" / f"easel-{VERSION}.mcpb"
    with zipfile.ZipFile(package, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in sorted(entries.items()):
            info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            archive.writestr(info, data)
    digest = hashlib.sha256(package.read_bytes()).hexdigest()
    (ROOT / "dist" / "mcpb.sha256").write_text(f"{digest}  {package.name}\n")
    document = {
        "$schema": "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
        "name": "io.openmuse/easel",
        "title": "Easel 社媒管理",
        "description": "本机社媒素材加工和发布。安装后打开 Easel 自有引导，按需安装 Python、Playwright/Chromium、FFmpeg；真正发布需再次明确操作。",
        "version": VERSION,
        "repository": {"url": "https://github.com/openmuseai/Muse-Plugin-Ecosystem", "source": "github"},
        "packages": [{"registryType": "mcpb", "identifier": f"https://plugins.openmuseai.com/packages/{digest}.mcpb", "fileSha256": digest, "transport": {"type": "stdio"}}],
    }
    (ROOT / "dist" / "server.json").write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n")
    print(package)
    return package


if __name__ == "__main__":
    main()
