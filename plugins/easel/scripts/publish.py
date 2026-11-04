"""Submit the already-built Easel MCPB to an MCP Registry review queue."""
from __future__ import annotations

import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
VERSION = json.loads((ROOT / "package.json").read_text())["version"]


def request(url: str, token: str, method: str, data: bytes) -> dict:
    kind = "application/json" if method == "POST" else "application/octet-stream"
    with urlopen(Request(url, data=data, method=method, headers={"Authorization": f"Bearer {token}", "Content-Type": kind}), timeout=60) as response:
        return json.load(response)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--registry", required=True)
    parser.add_argument("--public-origin", help="Public HTTPS origin when submitting through a private tunnel")
    parser.add_argument("--token", default=os.environ.get("MARKET_DEVELOPER_TOKEN"))
    parser.add_argument("--bundle", type=Path, default=ROOT / "dist" / f"easel-{VERSION}.mcpb")
    args = parser.parse_args()
    token = args.token or getpass.getpass("Developer token: ")
    if not token:
        parser.error("Developer token required")
    bundle = args.bundle.read_bytes()
    digest = hashlib.sha256(bundle).hexdigest()
    origin = args.registry.rstrip("/")
    public = (args.public_origin or args.registry).rstrip("/")
    package_url = f"{public}/packages/{digest}.mcpb"
    request(f"{origin}/packages/{digest}.mcpb", token, "PUT", bundle)
    document = json.loads((ROOT / "dist" / "server.json").read_text())
    if document["version"] != VERSION or document["packages"][0]["fileSha256"] != digest:
        parser.error("Review metadata is stale; run npm test to rebuild the bundle")
    document["packages"][0]["identifier"] = package_url
    result = request(f"{origin}/v0.1/publish", token, "POST", json.dumps(document, ensure_ascii=False).encode())
    print(json.dumps({"submissionId": result["_meta"]["submissionId"], "state": result["_meta"]["status"], "sha256": digest, "server": document["name"], "version": VERSION}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
