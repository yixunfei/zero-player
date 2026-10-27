"""Generate platform icons from the supplied logo (requires Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parent.parent


def main() -> None:
    image = Image.open(ROOT / 'assets/brand/logo.jpg').convert('RGB')
    square = ImageOps.fit(image, (1024, 1024), method=Image.Resampling.LANCZOS)
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        folder = ROOT / 'android/app/src/main/res' / f'mipmap-{density}'
        folder.mkdir(parents=True, exist_ok=True)
        square.resize((size, size), Image.Resampling.LANCZOS).save(folder / 'ic_launcher.png')
    square.save(ROOT / 'windows/runner/resources/app_icon.ico', format='ICO',
                sizes=[(n, n) for n in [16, 24, 32, 48, 64, 128, 256]])
    banner = Image.new('RGB', (320, 180), '#113c48')
    banner.paste(square.resize((180, 180), Image.Resampling.LANCZOS), (0, 0))
    draw = ImageDraw.Draw(banner)
    font = ImageFont.load_default(size=21)
    draw.multiline_text((250, 90), 'ZERO\nPLAYER', font=font, anchor='mm',
                        align='center', fill='#efffff', spacing=8)
    folder = ROOT / 'android/app/src/main/res/drawable-xhdpi'
    folder.mkdir(exist_ok=True)
    banner.save(folder / 'tv_banner.png')


if __name__ == '__main__':
    main()
