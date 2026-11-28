"""Standalone MCP Registry compatible catalog with moderated MCPB uploads.

The public client surface is the MCP Registry v0.1 API and MCPB files. Upload
and moderation routes are service administration, never a plugin/Host protocol.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sqlite3
import threading
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from io import BytesIO
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

MAX_PACKAGE = 32 * 1024 * 1024
DIGEST = re.compile(r"^[0-9a-f]{64}$")
SERVER_NAME = re.compile(r"^[a-z0-9][a-z0-9.-]*/[a-z0-9][a-z0-9._-]*$")


class Market(ThreadingHTTPServer):
    def __init__(self, address, root: Path, developer_token: str, reviewer_token: str):
        super().__init__(address, Handler)
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        (root / "packages").mkdir(exist_ok=True)
        self.developer_token = developer_token
        self.reviewer_token = reviewer_token
        self.lock = threading.Lock()
        self.db = sqlite3.connect(root / "market.sqlite3", check_same_thread=False)
        self.db.execute("""CREATE TABLE IF NOT EXISTS submissions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            version TEXT NOT NULL,
            document TEXT NOT NULL,
            digest TEXT NOT NULL,
            state TEXT NOT NULL,
            review TEXT NOT NULL DEFAULT '',
            UNIQUE(name, version)
        )""")
        self.db.commit()


class Handler(BaseHTTPRequestHandler):
    server: Market

    def _json(self, status: int, payload: object) -> None:
        data = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _auth(self, reviewer: bool = False) -> bool:
        expected = self.server.reviewer_token if reviewer else self.server.developer_token
        if expected and self.headers.get("Authorization") == f"Bearer {expected}":
            return True
        self._json(401, {"error": "Bearer token required"})
        return False

    def _body(self, limit: int) -> bytes:
        length = int(self.headers.get("Content-Length", "-1"))
        if length < 0 or length > limit:
            raise ValueError("Invalid Content-Length")
        data = self.rfile.read(length)
        if len(data) != length:
            raise ValueError("Incomplete body")
        return data

    def _package_path(self, digest: str) -> Path:
        return self.server.root / "packages" / f"{digest}.mcpb"

    def _origin(self) -> str:
        return f"http://{self.headers.get('Host', 'localhost')}"

    def do_PUT(self) -> None:
        path = urlsplit(self.path).path
        match = re.fullmatch(r"/packages/([0-9a-f]{64})\.mcpb", path)
        if not match:
            return self._json(404, {"error": "Not found"})
        if not self._auth():
            return
        try:
            data = self._body(MAX_PACKAGE)
            digest = hashlib.sha256(data).hexdigest()
            if digest != match.group(1):
                raise ValueError("SHA-256 mismatch")
            with zipfile.ZipFile(BytesIO(data)) as archive:
                names = archive.namelist()
                if len(names) > 256 or "manifest.json" not in names:
                    raise ValueError("Invalid MCPB archive")
                if any(name.startswith("/") or ".." in Path(name).parts for name in names):
                    raise ValueError("Unsafe archive path")
                manifest = json.loads(archive.read("manifest.json"))
                entry = manifest.get("server", {}).get("entry_point", "")
                if manifest.get("manifest_version") not in {"0.3", "0.4"} or entry not in names:
                    raise ValueError("Invalid MCPB manifest")
                if manifest.get("server", {}).get("type") != "node":
                    raise ValueError("Only bundled Node MCPB is enabled")
            target = self._package_path(digest)
            if not target.exists():
                target.write_bytes(data)
            self._json(201, {"digest": f"sha256:{digest}"})
        except (ValueError, KeyError, zipfile.BadZipFile, json.JSONDecodeError) as error:
            self._json(400, {"error": str(error)})

    def do_POST(self) -> None:
        path = urlsplit(self.path).path
        if path == "/v0.1/publish":
            if not self._auth():
                return
            return self._publish()
        match = re.fullmatch(r"/internal/reviews/(\d+)/(approve|reject)", path)
        if match:
            if not self._auth(reviewer=True):
                return
            return self._review(int(match.group(1)), match.group(2))
        self._json(404, {"error": "Not found"})

    def _publish(self) -> None:
        try:
            document = json.loads(self._body(64 * 1024))
            name, version = document["name"], document["version"]
            if not isinstance(name, str) or not SERVER_NAME.fullmatch(name):
                raise ValueError("Invalid MCP Registry server name")
            if not isinstance(version, str) or not re.fullmatch(r"\d+\.\d+\.\d+", version):
                raise ValueError("Exact semantic version required")
            packages = document["packages"]
            if not isinstance(packages, list) or len(packages) != 1:
                raise ValueError("One MCPB package required")
            package = packages[0]
            remotes = document.get("remotes", [])
            if not isinstance(remotes, list) or any(not isinstance(item, dict) for item in remotes):
                raise ValueError("Invalid remote endpoint list")
            for remote in remotes:
                url = urlsplit(remote.get("url", ""))
                if remote.get("type") != "streamable-http" or not (
                    url.scheme == "https" or
                    (url.scheme == "http" and url.hostname in {"127.0.0.1", "localhost"})
                ):
                    raise ValueError("Remote must use MCP Streamable HTTP over HTTPS")
            digest = package["fileSha256"]
            identifier = package["identifier"]
            if (package.get("registryType") != "mcpb" or
                package.get("transport") != {"type": "stdio"} or
                not isinstance(digest, str) or not DIGEST.fullmatch(digest) or
                identifier != f"{self._origin()}/packages/{digest}.mcpb"):
                raise ValueError("Invalid MCPB package descriptor")
            artifact = self._package_path(digest)
            if not artifact.exists():
                raise ValueError("Upload package first")
            with zipfile.ZipFile(artifact) as archive:
                manifest = json.loads(archive.read("manifest.json"))
            if manifest["version"] != version:
                raise ValueError("Bundle version differs from registry version")
            if not isinstance(document.get("description"), str):
                raise ValueError("Description required")
            with self.server.lock:
                cursor = self.server.db.execute(
                    "INSERT INTO submissions(name,version,document,digest,state) VALUES(?,?,?,?,?)",
                    (name, version, json.dumps(document), digest, "pending"),
                )
                self.server.db.commit()
            self._json(202, {"server": document, "_meta": {"status": "pending", "submissionId": cursor.lastrowid}})
        except (ValueError, KeyError, TypeError, json.JSONDecodeError, sqlite3.IntegrityError) as error:
            self._json(400, {"error": str(error)})

    def _review(self, submission_id: int, decision: str) -> None:
        try:
            payload = json.loads(self._body(16 * 1024))
            note = payload.get("note", "")
            if not isinstance(note, str):
                raise ValueError("Invalid review note")
            with self.server.lock:
                current = self.server.db.execute("SELECT state FROM submissions WHERE id=?", (submission_id,)).fetchone()
                if current is None or current[0] != "pending":
                    raise ValueError("Submission is not pending")
                state = "approved" if decision == "approve" else "rejected"
                self.server.db.execute(
                    "UPDATE submissions SET state=?,review=? WHERE id=?", (state, note, submission_id)
                )
                self.server.db.commit()
            self._json(200, {"id": submission_id, "state": state})
        except (ValueError, json.JSONDecodeError) as error:
            self._json(400, {"error": str(error)})

    def do_GET(self) -> None:
        parsed = urlsplit(self.path)
        if parsed.path == "/v0.1/servers":
            return self._list(parse_qs(parsed.query))
        match = re.fullmatch(r"/packages/([0-9a-f]{64})\.mcpb", parsed.path)
        if match:
            artifact = self._package_path(match.group(1))
            row = self.server.db.execute(
                "SELECT 1 FROM submissions WHERE digest=? AND state='approved'", (match.group(1),)
            ).fetchone()
            if not row or not artifact.exists():
                return self._json(404, {"error": "Not published"})
            data = artifact.read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "application/octet-stream")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "public, max-age=31536000, immutable")
            self.end_headers()
            return self.wfile.write(data)
        match = re.fullmatch(r"/v0.1/submissions/(\d+)", parsed.path)
        if match:
            if not self._auth():
                return
            row = self.server.db.execute(
                "SELECT name,version,state,review FROM submissions WHERE id=?", (int(match.group(1)),)
            ).fetchone()
            return self._json(200 if row else 404, dict(zip(("name", "version", "state", "review"), row)) if row else {"error": "Not found"})
        self._json(404, {"error": "Not found"})

    def _list(self, query: dict[str, list[str]]) -> None:
        search = query.get("search", [""])[0].lower()
        try:
            cursor = max(0, int(query.get("cursor", ["0"])[0]))
        except ValueError:
            return self._json(400, {"error": "Invalid cursor"})
        rows = self.server.db.execute(
            "SELECT id,name,version,document FROM submissions WHERE state='approved'"
        ).fetchall()
        latest = {}
        for ident, name, version, raw in rows:
            previous = latest.get(name)
            if previous is None or tuple(map(int, version.split("."))) > tuple(map(int, previous[1].split("."))):
                latest[name] = (ident, version, raw)
        filtered = []
        for name in sorted(latest):
            _, _, raw = latest[name]
            document = json.loads(raw)
            if search and search not in (name + " " + document.get("description", "")).lower():
                continue
            filtered.append(document)
        servers = []
        for document in filtered[cursor:cursor + 50]:
            servers.append({"server": document, "_meta": {"status": "active", "isLatest": True}})
        metadata = {"nextCursor": str(cursor + 50)} if cursor + 50 < len(filtered) else {}
        self._json(200, {"servers": servers, "metadata": metadata})


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--listen", default="127.0.0.1:8765")
    parser.add_argument("--data", type=Path, default=Path(".market-data"))
    args = parser.parse_args()
    host, port = args.listen.rsplit(":", 1)
    developer_token = os.environ.get("MARKET_DEVELOPER_TOKEN", "")
    reviewer_token = os.environ.get("MARKET_REVIEWER_TOKEN", "")
    if not developer_token or not reviewer_token or developer_token == reviewer_token:
        parser.error("Set distinct MARKET_DEVELOPER_TOKEN and MARKET_REVIEWER_TOKEN")
    service = Market((host, int(port)), args.data, developer_token, reviewer_token)
    print(f"MCP registry listening at http://{host}:{port}", flush=True)
    service.serve_forever()


if __name__ == "__main__":
    main()
