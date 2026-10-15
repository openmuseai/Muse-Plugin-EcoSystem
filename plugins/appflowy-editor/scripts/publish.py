"""Upload the standard MCPB and submit a standard MCP Registry server document."""
import argparse
import hashlib
import json
from pathlib import Path
from urllib.request import Request, urlopen

parser = argparse.ArgumentParser()
parser.add_argument("--registry", required=True)
parser.add_argument("--token", required=True)
parser.add_argument("--remote", required=True, help="MCP Streamable HTTP endpoint, HTTPS in production")
parser.add_argument("--bundle", type=Path, default=Path(__file__).resolve().parents[1] / "dist/appflowy-editor-0.1.0.mcpb")
args = parser.parse_args()
origin = args.registry.rstrip("/")
data = args.bundle.read_bytes()
digest = hashlib.sha256(data).hexdigest()
package = f"{origin}/packages/{digest}.mcpb"
def request(url, method, body):
    if isinstance(body, dict):
        body = json.dumps(body).encode()
        content_type = "application/json"
    else:
        content_type = "application/octet-stream"
    with urlopen(Request(url, data=body, method=method, headers={"Authorization": f"Bearer {args.token}", "Content-Type": content_type}), timeout=30) as response:
        return json.load(response)
request(package, "PUT", data)
document = {
    "$schema": "https://static.modelcontextprotocol.io/schemas/2025-12-11/server.schema.json",
    "name": "io.openmuse/appflowy-editor",
    "title": "AppFlowy Editor",
    "description": "Rich text editor for Desktop and Mobile, delivered via MCP Apps.",
    "version": "0.1.0",
    "repository": {"url": "https://github.com/AppFlowy-IO/appflowy-editor", "source": "github"},
    "packages": [{"registryType": "mcpb", "identifier": package, "fileSha256": digest, "transport": {"type": "stdio"}}],
    "remotes": [{"type": "streamable-http", "url": args.remote}],
}
response = request(origin + "/v0.1/publish", "POST", document)
print(json.dumps({"submissionId": response["_meta"]["submissionId"], "state": response["_meta"]["status"], "sha256": digest}, indent=2))
