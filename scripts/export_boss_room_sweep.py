#!/usr/bin/env python3
"""Package the verified Blender #210 camera samples without shipping authoring metadata."""

import argparse
import hashlib
import json
import math
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "docs/boss-room-cameras-210/camera-manifest.json"
OUTPUT = ROOT / "DescentAuthorized/Core/Resources/BossRoomSweepTracks.json"


def export(source: Path) -> bytes:
    data = source.read_bytes()
    manifest = json.loads(data)
    fps, duration = manifest["fps"], manifest["duration_seconds"]
    assert fps == 30 and duration == 12, "Recheck runtime timing before changing the authored timeline"
    rooms = []
    assert sorted(room["floor"] for room in manifest["rooms"]) == list(range(1, 10))
    for room in sorted(manifest["rooms"], key=lambda room: room["floor"]):
        settings = [pose["camera_settings"] for pose in room["poses"]]
        camera = settings[0]
        render = room["render_settings"]
        aspect = render["resolution_x"] * render["pixel_aspect_x"] / (
            render["resolution_y"] * render["pixel_aspect_y"]
        )
        # AUTO and HORIZONTAL are equivalent for these landscape authored cameras.
        assert aspect >= 1
        assert all(item["sensor_fit"] in ("AUTO", "HORIZONTAL") for item in settings)
        assert all(item["sensor_width_mm"] == camera["sensor_width_mm"] for item in settings)
        assert all(item["sensor_height_mm"] == camera["sensor_height_mm"] for item in settings)
        samples = []
        assert len(room["samples"]) == int(duration * fps) + 1
        for index, sample in enumerate(room["samples"]):
            assert sample["frame"] == index + 1
            assert abs(sample["seconds"] - index / fps) < 1e-9
            row = sample["position"] + sample["quaternion_wxyz"] + [
                sample["lens_mm"], sample["shift_x"], sample["shift_y"]
            ]
            assert len(row) == 10 and all(math.isfinite(value) for value in row)
            assert abs(sum(value * value for value in row[3:7]) - 1) < 1e-5
            samples.append(row)
        rooms.append({
            "floor": room["floor"],
            "sensorWidth": camera["sensor_width_mm"],
            "sensorHeight": camera["sensor_height_mm"],
            "sensorFit": "HORIZONTAL",
            "aspectRatio": aspect,
            "nearClip": min(item["clip_start_m"] for item in settings),
            "farClip": max(item["clip_end_m"] for item in settings),
            "samples": samples,
        })
    document = {
        "version": 1,
        "sourceManifestSHA256": hashlib.sha256(data).hexdigest(),
        "coordinates": "meters, Z-up; row=position XYZ, quaternion WXYZ, lens mm, shift XY",
        "fps": fps,
        "duration": duration,
        "rooms": rooms,
    }
    return (json.dumps(document, separators=(",", ":"), ensure_ascii=False) + "\n").encode()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="Fail if the bundled data differs from Blender samples")
    args = parser.parse_args()
    expected = export(SOURCE)
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_bytes() != expected:
            parser.error("Bundled sweep data is stale; run this exporter without --check")
        print("Boss camera bundle matches all 3,249 Blender samples")
    else:
        OUTPUT.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT.write_bytes(expected)
        print(f"Wrote {len(expected):,} bytes to {OUTPUT.relative_to(ROOT)}")
