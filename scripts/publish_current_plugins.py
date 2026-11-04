#!/usr/bin/env python3
"""Preflight current MCPB packages, then submit missing versions for review."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import zipfile
from pathlib import Path
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
SCHEMA = "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json"


def request(url: str, *, method: str = "GET", token: str = "", data: bytes | None = None) -> dict:
    headers = {}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if data is not None:
        headers["Content-Type"] = "application/json" if method == "POST" else "application/octet-stream"
    with urlopen(Request(url, data=data, method=method, headers=headers), timeout=120) as response:
        return json.load(response)


def current_bundles(public_origin: str) -> list[tuple[Path, dict]]:
    ready = []
    for plugin in sorted((ROOT / "plugins").iterdir()):
        package = plugin / "package.json"
        if not package.is_file():
            continue  # Source-only engine or evidence directory.
        version = json.loads(package.read_text())["version"]
        bundles = list((plugin / "dist").glob(f"*-{version}.mcpb"))
        if len(bundles) != 1:
            raise RuntimeError(f"expected one current MCPB for {plugin.name}@{version}")
        bundle = bundles[0]
        with zipfile.ZipFile(bundle) as archive:
            manifest = json.loads(archive.read("manifest.json"))
        if manifest["version"] != version:
            raise RuntimeError(f"bundle identity mismatch: {bundle}")
        digest = hashlib.sha256(bundle.read_bytes()).hexdigest()
        metadata = plugin / "dist/server.json"
        document = json.loads(metadata.read_text()) if metadata.is_file() else {
            "$schema": SCHEMA,
            "name": f"io.openmuse/{manifest['name']}",
            "title": manifest.get("display_name", manifest["name"]),
            "description": manifest["description"],
            "version": version,
        }
        if document["name"] != f"io.openmuse/{manifest['name']}" or document["version"] != version:
            raise RuntimeError(f"server metadata identity mismatch: {plugin.name}")
        document["packages"] = [{
            "registryType": "mcpb",
            "identifier": f"{public_origin}/packages/{digest}.mcpb",
            "fileSha256": digest,
            "transport": {"type": "stdio"},
        }]
        ready.append((bundle, document))
    return ready


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--registry", default="https://plugins.openmuseai.com")
    parser.add_argument("--public-origin", default="https://plugins.openmuseai.com")
    parser.add_argument("--publish", action="store_true", help="upload and submit missing versions")
    args = parser.parse_args()
    origin = args.registry.rstrip("/")
    public = args.public_origin.rstrip("/")
    catalog = request(f"{public}/v0.1/servers")
    active = {
        (server["server"]["name"], server["server"]["version"]): server["server"]
        for server in catalog["servers"]
    }
    token = os.environ.get("MARKET_DEVELOPER_TOKEN", "")
    if args.publish and not token:
        parser.error("MARKET_DEVELOPER_TOKEN is required for publishing")
    results = []
    for bundle, document in current_bundles(public):
        name, version = document["name"], document["version"]
        digest = document["packages"][0]["fileSha256"]
        existing = active.get((name, version))
        if existing:
            existing_digest = existing["packages"][0]["fileSha256"]
            if existing_digest != digest:
                raise RuntimeError(f"immutable version conflict: {name}@{version}")
            status = "approved"
        elif args.publish:
            request(f"{origin}/v0.1/packages/{digest}.mcpb", method="PUT", token=token, data=bundle.read_bytes())
            result = request(
                f"{origin}/v0.1/publish", method="POST", token=token,
                data=json.dumps(document, ensure_ascii=False).encode(),
            )
            status = result["_meta"]["status"]
        else:
            status = "ready"
        results.append({"name": name, "version": version, "sha256": digest, "status": status})
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
