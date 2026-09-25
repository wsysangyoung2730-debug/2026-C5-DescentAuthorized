"""Compare an installed/built app's Reality resources with this checkout.

Usage: python3 docs/reality-assets/verify_bundled_reality.py /path/App.app
Read-only: never removes the app, its save data, or build caches.
"""
import argparse
import hashlib
import json
from pathlib import Path


def digest(path):
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(chunk)
    return checksum.hexdigest()


def compare(source, bundled):
    source_files = {p.relative_to(source): p for p in source.rglob("*") if p.is_file()}
    bundled_files = {p.relative_to(bundled): p for p in bundled.rglob("*") if p.is_file()}
    mismatches = []
    for relative, path in sorted(source_files.items()):
        target = bundled_files.get(relative)
        if target is None:
            mismatches.append({"path": str(relative), "reason": "missing"})
        elif digest(path) != digest(target):
            mismatches.append({"path": str(relative), "reason": "different",
                               "sourceSHA256": digest(path), "bundleSHA256": digest(target)})
    extras = sorted(str(p) for p in bundled_files.keys() - source_files.keys())
    return {"source": str(source), "bundle": str(bundled),
            "expectedFiles": len(source_files), "bundledFiles": len(bundled_files),
            "mismatches": mismatches, "extraFiles": extras,
            "matches": bool(source_files) and not mismatches and not extras}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    source = Path(__file__).resolve().parents[2] / "DescentAuthorized/Resources/Reality"
    bundled = args.app.resolve() / "Reality"
    if not source.is_dir() or not bundled.is_dir():
        parser.error("Both checkout and app must contain a Reality resource directory")
    report = compare(source, bundled)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"Reality bundle: {report['expectedFiles']} expected files; "
          f"{len(report['mismatches'])} missing/changed; {len(report['extraFiles'])} extra")
    for mismatch in report["mismatches"][:12]:
        print(mismatch["reason"], mismatch["path"])
    if not report["matches"]:
        print("Build/install from this checkout before testing. See --report for the full comparison.")
    return 0 if report["matches"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
