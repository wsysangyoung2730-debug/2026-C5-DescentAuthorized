"""Validate captured runtime camera invariants, not just source USD metadata.

Usage: python3 validate_render_diagnostics.py path/to/RenderDiagnostics
An optional second directory compares the same run on another device.
"""
import json
import math
import sys
from pathlib import Path


def close(a, b, tolerance=1e-4):
    return max(abs(x - y) for x, y in zip(a, b)) < tolerance


def validate(directory):
    reports = [json.loads((directory / (name + ".json")).read_text())
               for name in ("01-baseline", "02-yaw", "03-fallen")]
    baseline, yaw, fallen = reports
    for report in reports:
        assert report["environmentLoaded"], "Environment missing from comparison"
        for key in ("rootMatrix", "authoredCamera", "entityCamera", "renderedCamera"):
            matrix = report[key]
            assert len(matrix) == 16 and all(map(math.isfinite, matrix)), key
            for column in (0, 4, 8):
                length = math.sqrt(sum(v * v for v in matrix[column:column + 3]))
                assert abs(length - 1) < 1e-4, (key, "not meter scale", length)
        assert close(report["entityCamera"], report["renderedCamera"]), "Wrong active camera"
        assert close(report["rootMatrix"][8:11], [0, 1, 0]), "Authored up is not world Y"
        assert abs(report["fov"] - baseline["fov"]) < 1e-4, "Unexpected FOV change"
    assert close(baseline["entityCamera"][12:15], yaw["entityCamera"][12:15]), "Yaw moved camera"
    assert abs(baseline["entityCamera"][5] - yaw["entityCamera"][5]) < 1e-4, "Yaw tilted up vector"
    distance = math.dist(baseline["entityCamera"][12:15], fallen["entityCamera"][12:15])
    assert 0.1 < distance < 1.0, ("Fall escaped room scale", distance)
    print("PASS", directory, baseline["scene"], baseline["os"], baseline["quality"])
    return reports


if __name__ == "__main__":
    runs = [validate(Path(path)) for path in sys.argv[1:]]
    assert runs, "Provide at least one diagnostic directory"
    for other in runs[1:]:
        for a, b in zip(runs[0], other):
            assert (a["scene"], a["quality"], a["camera"]) == (b["scene"], b["quality"], b["camera"])
            for key in ("rootMatrix", "authoredCamera", "entityCamera", "renderedCamera"):
                assert close(a[key], b[key]), (a["event"], key, "platform mismatch")
    if len(runs) > 1:
        print("PASS cross-platform transforms")
