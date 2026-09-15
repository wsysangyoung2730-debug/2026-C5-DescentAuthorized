import hashlib
import json
import shutil
import sys
import unicodedata
from pathlib import Path

from PIL import Image, ImageOps


plan_path = Path(sys.argv[1])
plan = json.loads(plan_path.read_text())
output = Path(plan["output"])
output.mkdir(parents=True, exist_ok=True)
cap = int(plan["cap"])
result = {}
content_paths = {}


def normalized(path):
    return unicodedata.normalize("NFC", str(Path(path).resolve()))


for source_text in plan["sources"]:
    source = Path(source_text)
    source_key = normalized(source)
    lower_name = source.name.lower()
    if source.suffix.lower() not in {".png", ".jpg", ".jpeg", ".exr"}:
        target = output / unicodedata.normalize("NFC", source.name)
        shutil.copy2(source, target)
    elif source.suffix.lower() == ".exr":
        target = output / unicodedata.normalize("NFC", source.name)
        shutil.copy2(source, target)
    else:
        with Image.open(source) as opened:
            image = ImageOps.exif_transpose(opened)
            if max(image.size) > cap:
                ratio = cap / max(image.size)
                image = image.resize(
                    (max(1, round(image.width * ratio)), max(1, round(image.height * ratio))),
                    Image.Resampling.LANCZOS,
                )
            opaque = image.mode not in {"RGBA", "LA"}
            if image.mode in {"RGBA", "LA"}:
                opaque = image.getchannel("A").getextrema() == (255, 255)
            make_jpeg = "basecolor" in lower_name and opaque
            suffix = ".jpg" if make_jpeg else ".png"
            stem = unicodedata.normalize("NFC", source.name)
            while Path(stem).suffix.lower() in {".png", ".jpg", ".jpeg"}:
                stem = Path(stem).stem
            target = output / f"{stem}{suffix}"
            collision = 1
            while target.exists():
                target = output / f"{stem}_{collision}{suffix}"
                collision += 1
            if make_jpeg:
                image.convert("RGB").save(
                    target,
                    format="JPEG",
                    quality=92,
                    subsampling=0,
                    optimize=True,
                )
            else:
                if image.mode == "P":
                    image = image.convert("RGBA")
                image.save(target, format="PNG", optimize=True)

    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    if digest in content_paths:
        target.unlink()
        target = output / content_paths[digest]
    else:
        content_paths[digest] = target.name
    result[source_key] = target.name

plan_path.with_suffix(".result.json").write_text(
    json.dumps(result, ensure_ascii=False, indent=2)
)
