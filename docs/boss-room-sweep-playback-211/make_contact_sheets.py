"""Arrange real simulator captures; no scene pixels are synthesized or retouched."""
import argparse
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

parser = argparse.ArgumentParser()
parser.add_argument("raw", type=Path, help="Directory of Fxx-left/wide/right/return/battle/hud.png")
args = parser.parse_args()
output = Path(__file__).resolve().parent / "evidence"
output.mkdir(exist_ok=True)
phases = ("left", "wide", "right", "return", "battle", "hud")
for floor in range(1, 10):
    paths = [args.raw / f"F{floor:02}-{phase}.png" for phase in phases]
    if not all(path.exists() for path in paths):
        continue
    sheet = Image.new("RGB", (1500, 730), (16, 17, 20))
    draw = ImageDraw.Draw(sheet)
    for index, (phase, path) in enumerate(zip(phases, paths)):
        frame = Image.open(path).convert("RGB")
        if phase == "hud" and frame.height > frame.width:
            # simctl captures the sensor framebuffer; this device is landscape-right.
            frame = frame.transpose(Image.Transpose.ROTATE_270)
        frame = ImageOps.contain(frame, (500, 335))
        x, y = index % 3 * 500, index // 3 * 365
        sheet.paste(frame, (x + (500 - frame.width) // 2, y + 25 + (335 - frame.height) // 2))
        draw.text((x + 12, y + 7), f"F{floor:02} / {phase}", fill="white")
    sheet.save(output / f"F{floor:02}-runtime.jpg", quality=88)
