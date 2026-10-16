"""Upload the standard MCPB and submit a standard MCP Registry server document."""
import argparse
import hashlib
import json
import os
from pathlib import Path
from urllib.request import Request, urlopen

parser = argparse.ArgumentParser()
parser.add_argument("--registry", required=True)
parser.add_argument("--public-origin", help="Public registry origin when publishing through a private admin tunnel")
parser.add_argument("--token", default=os.environ.get("MARKET_DEVELOPER_TOKEN"), help="Defaults to MARKET_DEVELOPER_TOKEN")
parser.add_argument("--remote", required=True, help="MCP Streamable HTTP endpoint, HTTPS in production")
parser.add_argument("--bundle", type=Path, default=Path(__file__).resolve().parents[1] / "dist/appflowy-editor-0.1.4.mcpb")
args = parser.parse_args()
if not args.token:
    parser.error("--token or MARKET_DEVELOPER_TOKEN is required")
origin = args.registry.rstrip("/")
public_origin = (args.public_origin or args.registry).rstrip("/")
data = args.bundle.read_bytes()
digest = hashlib.sha256(data).hexdigest()
package = f"{public_origin}/packages/{digest}.mcpb"
def request(url, method, body):
    if isinstance(body, dict):
        body = json.dumps(body).encode()
        content_type = "application/json"
    else:
        content_type = "application/octet-stream"
    with urlopen(Request(url, data=body, method=method, headers={"Authorization": f"Bearer {args.token}", "Content-Type": content_type}), timeout=30) as response:
        return json.load(response)
request(f"{origin}/packages/{digest}.mcpb", "PUT", data)
document = {
    "$schema": "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
    "name": "io.openmuse/appflowy-editor",
    "title": "AppFlowy Editor",
    "description": "Rich text editor for Desktop and Mobile, delivered via MCP Apps.",
    "version": "0.1.4",
    "repository": {"url": "https://github.com/AppFlowy-IO/appflowy-editor", "source": "github"},
    "packages": [{"registryType": "mcpb", "identifier": package, "fileSha256": digest, "transport": {"type": "stdio"}}],
    "remotes": [{"type": "streamable-http", "url": args.remote}],
}
response = request(origin + "/v0.1/publish", "POST", document)
print(json.dumps({"submissionId": response["_meta"]["submissionId"], "state": response["_meta"]["status"], "sha256": digest}, indent=2))
