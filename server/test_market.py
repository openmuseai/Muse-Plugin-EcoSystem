from __future__ import annotations

import hashlib
import json
import tempfile
import threading
import unittest
import zipfile
from io import BytesIO
from pathlib import Path
from urllib.error import HTTPError
from urllib.request import Request, urlopen

from market import Market


class MarketFlowTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.market = Market(("127.0.0.1", 0), Path(self.temp.name), "dev", "review")
        self.thread = threading.Thread(target=self.market.serve_forever, daemon=True)
        self.thread.start()
        self.origin = f"http://127.0.0.1:{self.market.server_port}"

    def tearDown(self) -> None:
        self.market.shutdown()
        self.market.server_close()
        self.temp.cleanup()

    def request(self, path: str, *, method="GET", token="", body=b""):
        headers = {"Authorization": f"Bearer {token}"} if token else {}
        with urlopen(Request(self.origin + path, data=body if method != "GET" else None,
                             method=method, headers=headers), timeout=5) as response:
            return json.load(response)

    def test_upload_review_and_publication(self) -> None:
        stream = BytesIO()
        with zipfile.ZipFile(stream, "w") as archive:
            archive.writestr("manifest.json", json.dumps({
                "manifest_version": "0.3", "version": "1.0.0",
                "server": {"type": "node", "entry_point": "server/main.mjs"},
            }))
            archive.writestr("server/main.mjs", "process.stdin.resume()")
        data = stream.getvalue()
        digest = hashlib.sha256(data).hexdigest()
        package_url = f"{self.origin}/packages/{digest}.mcpb"
        with self.assertRaises(HTTPError) as missing:
            urlopen(package_url)
        self.assertEqual(missing.exception.code, 404)
        self.request(f"/packages/{digest}.mcpb", method="PUT", token="dev", body=data)
        document = {
            "name": "io.example/test", "version": "1.0.0", "description": "Example",
            "packages": [{"registryType": "mcpb", "identifier": package_url,
                          "fileSha256": digest, "transport": {"type": "stdio"}}],
            "remotes": [{"type": "streamable-http", "url": "http://127.0.0.1:8767/mcp"}],
        }
        with self.assertRaises(HTTPError) as invalid:
            self.request("/v0.1/publish", method="POST", token="dev",
                         body=json.dumps({**document, "remotes": ["bad"]}).encode())
        self.assertEqual(invalid.exception.code, 400)
        submitted = self.request("/v0.1/publish", method="POST", token="dev",
                                 body=json.dumps(document).encode())
        self.assertEqual(submitted["_meta"]["status"], "pending")
        self.assertEqual(self.request("/v0.1/servers")["servers"], [])
        with self.assertRaises(HTTPError) as pending:
            urlopen(package_url)
        self.assertEqual(pending.exception.code, 404)
        self.request(f"/internal/reviews/{submitted['_meta']['submissionId']}/approve",
                     method="POST", token="review", body=b'{"note":"approved"}')
        listed = self.request("/v0.1/servers")["servers"]
        self.assertEqual(listed[0]["server"]["name"], document["name"])
        self.assertEqual(listed[0]["server"]["remotes"], document["remotes"])
        with urlopen(package_url) as response:
            self.assertEqual(response.read(), data)


if __name__ == "__main__":
    unittest.main()
