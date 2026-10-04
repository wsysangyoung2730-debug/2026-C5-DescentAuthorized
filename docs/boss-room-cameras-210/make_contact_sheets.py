"""Assemble unretouched Blender geometry renders into review sheets."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parent
(root / 'contact-sheets').mkdir(exist_ok=True)
frames = [1, 52, 103, 160, 217, 277, 337]
labels = ['Left', 'Moving', 'Wide', 'Moving', 'Right', 'Moving', 'Return']
for floor in range(9, 0, -1):
    sheet = Image.new('RGB', (1800, 640), (18, 18, 20))
    draw = ImageDraw.Draw(sheet)
    for index, (frame, label) in enumerate(zip(frames, labels)):
        image = Image.open(root / 'frames' / f'F{floor:02d}_{frame:03d}.png')
        image.thumbnail((450, 282))
        x, y = (index % 4) * 450, (index // 4) * 320
        sheet.paste(image, (x + (450-image.width)//2, y+28))
        draw.text((x+12, y+8), f'F{floor:02d} | {(frame-1)/30:.1f}s | {label}', fill='white')
    draw.text((1365, 370), 'BLENDER CAMERA BLOCKING', fill='white')
    draw.text((1365, 400), 'Geometry preview / original aspect', fill=(170,170,175))
    draw.text((1365, 430), 'Not final materials or game lighting', fill=(170,170,175))
    sheet.save(root/'contact-sheets'/f'F{floor:02d}-sweep.jpg', quality=90)
