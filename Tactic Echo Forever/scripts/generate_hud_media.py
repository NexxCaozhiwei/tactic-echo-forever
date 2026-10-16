"""生成HUD圆角填充、细边框及遮罩；无外部素材依赖。"""
from pathlib import Path
from PIL import Image, ImageDraw

MEDIA = Path(__file__).resolve().parents[1] / "Media"

def rounded(name, size, radius, border=0):
    factor = 4
    image = Image.new("RGBA", (size * factor, size * factor))
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle((0, 0, size * factor - 1, size * factor - 1), radius * factor,
                           fill=(255, 255, 255, 255))
    if border:
        inset = round(border * factor)
        draw.rounded_rectangle((inset, inset, size * factor - inset - 1, size * factor - inset - 1),
                               max(0, (radius - border) * factor), fill=(255, 255, 255, 0))
    image = image.resize((size, size), Image.Resampling.LANCZOS)
    image.save(MEDIA / name)

if __name__ == "__main__":
    rounded("HUDRoundedFill.tga", 32, 8)
    rounded("HUDRoundedBorder.tga", 32, 8, 1.25)
    rounded("HUDIconMask.tga", 128, 16)
    rounded("HUDStatusDot.tga", 16, 8)
