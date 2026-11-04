#!/usr/bin/env python3
"""Stage a verified, read-only mirror of the approved MCP Registry catalog."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from urllib.parse import quote, urlparse
from urllib.request import urlopen

SOURCE = "https://plugins.openmuseai.com"


def fetch_json(url: str) -> dict:
    with urlopen(url, timeout=30) as response:
        if response.status != 200:
            raise RuntimeError(f"catalog HTTP {response.status}")
        return json.load(response)


def mirror_package(url: str, digest: str, destination: Path) -> None:
    if not url.startswith(SOURCE + "/packages/") or not url.endswith(f"/{digest}.mcpb"):
        raise ValueError(f"unexpected package URL: {url}")
    if len(digest) != 64 or any(char not in "0123456789abcdef" for char in digest):
        raise ValueError("invalid SHA-256 digest")
    if destination.is_file() and hashlib.sha256(destination.read_bytes()).hexdigest() == digest:
        return
    temporary = destination.with_suffix(".mcpb.tmp")
    actual = hashlib.sha256()
    with urlopen(url, timeout=120) as response, temporary.open("wb") as output:
        if response.status != 200:
            raise RuntimeError(f"package HTTP {response.status}")
        while chunk := response.read(1024 * 1024):
            actual.update(chunk)
            output.write(chunk)
    if actual.hexdigest() != digest:
        temporary.unlink(missing_ok=True)
        raise ValueError(f"package digest mismatch: {digest}")
    temporary.replace(destination)


def select_launch_servers(records: list[dict], manifest: dict) -> list[dict]:
    """Only distribute the exact approved release composition, or keep old state."""
    pins = manifest.get('officialMcp')
    if not isinstance(pins, list) or not pins:
        raise ValueError('launch manifest requires pinned MCP plugins')
    selected = []
    names = set()
    for pin in pins:
        name, version, digest = pin['name'], pin['version'], pin['sha256']
        if name in names or len(digest) != 64 or any(c not in '0123456789abcdef' for c in digest):
            raise ValueError('invalid or duplicate launch pin')
        names.add(name)
        matches = [r for r in records if r['server']['name'] == name and r['server']['version'] == version]
        if len(matches) != 1:
            raise ValueError(f'approved launch version unavailable: {name}@{version}')
        packages = [p for p in matches[0]['server'].get('packages', []) if p.get('registryType') == 'mcpb']
        if len(packages) != 1 or packages[0].get('fileSha256') != digest:
            raise ValueError(f'approved launch digest mismatch: {name}@{version}')
        selected.append(matches[0])
    return selected


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument("--public-origin", default="https://us.openmuseai.com")
    parser.add_argument('--launch-manifest', type=Path, help='Pin the overseas official launch composition')
    args = parser.parse_args()
    target_origin = args.public_origin.rstrip("/")
    if urlparse(target_origin).scheme != "https":
        parser.error("public origin must use HTTPS")
    destination = args.destination
    packages = destination / "packages"
    packages.mkdir(parents=True, exist_ok=True)
    servers: list[dict] = []
    cursor: str | None = None
    seen: set[str] = set()
    while True:
        url = SOURCE + "/v0.1/servers?limit=100"
        if cursor:
            url += "&cursor=" + quote(cursor, safe="")
        page = fetch_json(url)
        batch = page.get("servers")
        if not isinstance(batch, list):
            raise ValueError("invalid MCP Registry catalog")
        servers.extend(batch)
        metadata = page.get("metadata")
        cursor = (
            metadata.get("nextCursor") if isinstance(metadata, dict) else None
        ) or page.get("nextCursor")
        if not cursor:
            break
        if not isinstance(cursor, str) or cursor in seen or len(servers) > 1000:
            raise ValueError("invalid MCP Registry cursor")
        seen.add(cursor)

    if args.launch_manifest:
        servers = select_launch_servers(servers, json.loads(args.launch_manifest.read_text()))

    approved_digests: set[str] = set()
    for record in servers:
        server = record["server"]
        for package in server.get("packages", []):
            if package.get("registryType") != "mcpb":
                continue
            digest = package["fileSha256"].lower()
            mirror_package(package["identifier"], digest, packages / f"{digest}.mcpb")
            approved_digests.add(digest)
            package["identifier"] = f"{target_origin}/packages/{digest}.mcpb"
        for remote in server.get("remotes", []):
            url = remote.get("url", "")
            if url.startswith(SOURCE + "/"):
                remote["url"] = target_origin + url[len(SOURCE) :]

    payload = {"metadata": {}, "servers": servers}
    staged = destination / "catalog.json.tmp"
    staged.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    staged.replace(destination / "catalog.json")
    for artifact in packages.glob("*.mcpb"):
        if artifact.stem not in approved_digests:
            artifact.unlink()
    print(f"Mirrored {len(servers)} approved plugins to {destination}")


if __name__ == "__main__":
    main()
