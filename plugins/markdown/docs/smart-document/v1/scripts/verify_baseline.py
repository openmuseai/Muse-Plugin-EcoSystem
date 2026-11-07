#!/usr/bin/env python3
"""Read-only integrity and traceability checks for a frozen product baseline."""

import hashlib
import json
from pathlib import Path
import sys


BASELINE_ID = "SD-BL-1.2-20261105"


def verify(root):
    errors = []
    manifest = json.loads((root / "manifest.json").read_text())
    if manifest.get("baselineId") != BASELINE_ID:
        errors.append("Unexpected baselineId")
    entries = manifest.get("files", [])
    if not entries:
        errors.append("Empty manifest")
    names = set()
    for item in entries:
        name = item["path"]
        if name in names:
            errors.append("Duplicate entry: " + name)
        names.add(name)
        target = root / name
        if not target.resolve().is_relative_to(root.resolve()):
            errors.append("Path escapes baseline: " + name)
            continue
        if target.is_symlink() or not target.is_file():
            errors.append("Missing file or symlink: " + name)
            continue
        data = target.read_bytes()
        if len(data) != item["bytes"]:
            errors.append("Size mismatch: " + name)
        if hashlib.sha256(data).hexdigest() != item["sha256"]:
            errors.append("SHA-256 mismatch: " + name)
    actual = {str(p.relative_to(root)) for p in root.rglob("*") if p.is_file()}
    unexpected = actual - names - {"manifest.json"}
    errors.extend("Unlisted file: " + name for name in sorted(unexpected))
    trace = json.loads((root / "implementation-traceability.json").read_text())
    if trace.get("baselineId") != BASELINE_ID:
        errors.append("Traceability baseline mismatch")
    requirements = trace["requirements"]
    expected = {"SD-%02d" % i for i in range(1, 18)}
    if {r["id"] for r in requirements} != expected or len(requirements) != 17:
        errors.append("Expected exactly SD-01..SD-17")
    tasks = {"T%02d" % i for i in range(1, 25)}
    acceptance = {"AC-%02d" % i for i in range(1, 18)}
    for item in requirements + trace["functionalAlignment"] + trace["frames"]:
        if not item.get("tasks") or not set(item["tasks"]) <= tasks:
            errors.append("Invalid task coverage: " + item["id"])
        if not item.get("acceptance") or not set(item["acceptance"]) <= acceptance:
            errors.append("Invalid acceptance coverage: " + item["id"])
        if not set(item.get("requirements", [])) <= expected:
            errors.append("Invalid requirement reference: " + item["id"])
        if item.get("productStatus") != "unrun":
            errors.append("Product test status must remain unrun: " + item["id"])
    for key, prefix, count in [("functionalAlignment", "FA", 14), ("frames", "WF", 12)]:
        values = trace[key]
        if {v["id"] for v in values} != {"%s-%02d" % (prefix, i) for i in range(1, count + 1)} or len(values) != count:
            errors.append("Invalid coverage set: " + key)
    qa = json.loads((root / "wps-functional-review/screens/QA.json").read_text())
    if qa.get("errors") or len(qa.get("checks", [])) != 19:
        errors.append("Expected frozen prototype report: 19 checks, zero errors")
    return errors, len(entries)


if __name__ == "__main__":
    root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1] / "baselines/sd-v1.2-20261105"
    try:
        errors, count = verify(root)
    except (OSError, ValueError, KeyError, TypeError) as error:
        print("Baseline verification failed: " + str(error), file=sys.stderr)
        sys.exit(1)
    if errors:
        print("\n".join(errors), file=sys.stderr)
        sys.exit(1)
    print("%s: %d files verified; SD=17, FA=14, WF=12; prototype=19 passed; product tests=unrun" % (BASELINE_ID, count))
