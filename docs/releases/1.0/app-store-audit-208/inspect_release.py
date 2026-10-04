#!/usr/bin/env python3
"""Read-only Release bundle inventory; not an App Store validation substitute.

Usage: python3 inspect_release.py /path/DescentAuthorized.app --source-revision SHA --output report.json
Exit 0 means inspection completed, not that the app is ready to submit.
Uses the Python standard library and macOS `strings`/`otool` only.
"""
import argparse
import collections
import hashlib
import json
from pathlib import Path
import plistlib
import struct
import subprocess


def sha256(path):
    checksum = hashlib.sha256()
    with path.open("rb") as stream:
        for data in iter(lambda: stream.read(1024 * 1024), b""):
            checksum.update(data)
    return checksum.hexdigest()


def inspect(app, repo, source_revision):
    info = plistlib.loads((app / "Info.plist").read_bytes())
    binary = app / info["CFBundleExecutable"]
    privacy_file = app / "PrivacyInfo.xcprivacy"
    privacy = plistlib.loads(privacy_file.read_bytes()) if privacy_file.exists() else {}
    declared = {entry["NSPrivacyAccessedAPIType"]: entry.get("NSPrivacyAccessedAPITypeReasons", [])
                for entry in privacy.get("NSPrivacyAccessedAPITypes", [])}
    strings = subprocess.run(["strings", "-a", str(binary)], check=True,
                             capture_output=True, text=True).stdout
    dependencies = subprocess.run(["otool", "-L", str(binary)], check=True,
                                  capture_output=True, text=True).stdout.splitlines()[1:]
    files = sorted(p for p in app.rglob("*") if p.is_file())
    totals = collections.Counter()
    extensions = collections.Counter()
    for path in files:
        relative = path.relative_to(app)
        totals[relative.parts[0]] += path.stat().st_size
        extensions[path.suffix.lower() or "(none)"] += 1
    icon = repo / "DescentAuthorized/Resources/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png"
    png = icon.read_bytes()
    if png[:8] != b"\x89PNG\r\n\x1a\n" or png[12:16] != b"IHDR":
        raise ValueError("Expected PNG IHDR for the source App Store icon")
    width, height, depth, color_type = struct.unpack(">IIBB", png[16:26])
    # RGB (2) cannot contain an alpha channel. This is a source-icon observation.
    markers = ["--floor9-preview", "--glyph-fidelity", "--expansion-diagnostics",
               "--barrier-guide-diagnostics", "--room-warmup-diagnostics"]
    missing_boot_reason = "systemUptime" in strings and not declared.get(
        "NSPrivacyAccessedAPICategorySystemBootTime")
    warnings = []
    if missing_boot_reason:
        warnings.append("Release contains systemUptime but the bundled manifest has no SystemBootTime reason")
    if info.get("CFBundleDevelopmentRegion") != "ko" and "ko" not in info.get("CFBundleLocalizations", []):
        warnings.append("Korean UI has no Korean bundle language declaration; inspect metadata before submission")
    if any(marker in strings for marker in markers):
        warnings.append("A selected preview marker exists in the binary; inspect its reachability")
    return {
        "scope": "Unsigned device Release bundle; inspection only, not signing/ASC/device approval",
        "sourceRevisionProvidedByCaller": source_revision,
        "bundleInfo": info,
        "bundleBytes": sum(totals.values()),
        "bundleFileCount": len(files),
        "binaryBytes": binary.stat().st_size,
        "binarySHA256": sha256(binary),
        "topLevelBytes": dict(totals.most_common()),
        "extensionCounts": dict(sorted(extensions.items())),
        "largestFiles": [{"path": str(p.relative_to(app)), "bytes": p.stat().st_size}
                         for p in sorted(files, key=lambda p: p.stat().st_size, reverse=True)[:12]],
        "linkedLibraries": [line.strip() for line in dependencies],
        "bundledPrivacyManifest": privacy,
        "bundledPrivacySHA256": sha256(privacy_file) if privacy_file.exists() else None,
        "sourceIcon": {"width": width, "height": height, "bitDepth": depth,
                       "colorType": color_type, "rgbWithoutAlpha": color_type == 2,
                       "sha256": sha256(icon)},
        "releaseSystemUptimeSelectorPresent": "systemUptime" in strings,
        "selectedPreviewMarkers": {m: m in strings for m in markers},
        "bundledDocumentation": [str(p.relative_to(app)) for p in files if p.suffix.lower() in [".md", ".py", ".blend"]],
        "inspectionWarnings": warnings,
        "limitations": ["No exhaustive private API or executable reachability analysis",
                        "No compressed IPA or App Store thinning size measured",
                        "No distribution signing or App Store Connect validation",
                        "No real iPad performance or end-to-end gameplay certification"]
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("app", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--source-revision", required=True,
                        help="Source revision used to build the supplied app; not inferred from checkout")
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[4]
    report = inspect(args.app.resolve(), repo, args.source_revision)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(f"Inspected {report['bundleFileCount']} files / {report['bundleBytes']:,} bytes")
    for warning in report["inspectionWarnings"]:
        print("REVIEW:", warning)


if __name__ == "__main__":
    main()
