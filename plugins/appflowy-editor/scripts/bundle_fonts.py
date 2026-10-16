"""Pin Flutter Web's fallback fonts and copy them beside the offline site."""
import hashlib
import json
import os
import re
import shutil
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from urllib.request import urlopen

root = Path(__file__).resolve().parents[1]
flutter_binary = shutil.which("flutter")
flutter_root = Path(os.environ["FLUTTER_ROOT"]) if "FLUTTER_ROOT" in os.environ else Path(flutter_binary).resolve().parents[1]
engine = flutter_root / "bin/cache/flutter_web_sdk/lib/_engine/engine"
fallback_data = (engine / "font_fallback_data.dart").read_text()
font_code = (engine / "canvaskit/fonts.dart").read_text()
paths = set(re.findall(r"'([^']+\.woff2)'", fallback_data))
roboto = re.search(r"fontFallbackBaseUrl}([^']+\.woff2)'", font_code)
if roboto is None:
    raise SystemExit("Flutter Web Roboto fallback URL not found")
paths.add(roboto.group(1))
lock = root / "web/font-fallback-lock.json"
expected = json.loads(lock.read_text()) if lock.exists() else None
if expected is not None and set(expected) != paths:
    raise SystemExit("Flutter fallback font set changed; review and regenerate the lock")
cache = root / "web/.font-cache"
target = root / "web/build/web/font-fallback"

def fetch(path):
    destination = cache / path
    if not destination.exists():
        destination.parent.mkdir(parents=True, exist_ok=True)
        with urlopen(f"https://fonts.gstatic.com/s/{path}", timeout=30) as response:
            data = response.read()
        if not data.startswith(b"wOF2"):
            raise ValueError(f"Not a WOFF2 font: {path}")
        destination.write_bytes(data)
    data = destination.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if expected is not None and digest != expected[path]:
        raise ValueError(f"Font digest mismatch: {path}")
    output = target / path
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(destination, output)
    return path, digest, len(data)

target.mkdir(parents=True, exist_ok=True)
with ThreadPoolExecutor(max_workers=16) as pool:
    results = [future.result() for future in as_completed(pool.submit(fetch, path) for path in sorted(paths))]
if expected is None:
    lock.write_text(json.dumps({path: digest for path, digest, _ in sorted(results)}, indent=2) + "\n")
print(f"Bundled {len(results)} fallback fonts ({sum(size for _, _, size in results) / 1024 / 1024:.1f} MiB)")

licenses = root / "licenses/fonts"
licenses.mkdir(parents=True, exist_ok=True)
def fetch_license(family):
    notice = licenses / f"{family}-OFL.txt"
    if notice.exists():
        return
    with urlopen(f"https://raw.githubusercontent.com/google/fonts/main/ofl/{family}/OFL.txt", timeout=30) as response:
        source = response.read().decode("utf-8")
        notice.write_text("\n".join(line.rstrip() for line in source.splitlines()) + "\n")
with ThreadPoolExecutor(max_workers=16) as pool:
    list(pool.map(fetch_license, sorted({path.split("/", 1)[0] for path in paths})))
