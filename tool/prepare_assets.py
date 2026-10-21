"""Regenerate bundled fonts/icons. Requires Pillow and fonttools (development only).

Run from the repository root after installing those packages in your Python env.
Sources are downloaded only when absent; generated assets are committed, so normal
Flutter development and builds do not require Python or external font requests.
"""
from pathlib import Path
import os
import urllib.request

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'build/font-source'
ASSETS = ROOT / 'assets/fonts'
SOURCE.mkdir(parents=True, exist_ok=True)
ASSETS.mkdir(parents=True, exist_ok=True)

FONTS = {
    'NotoSansSC': ('notosanssc', 'NotoSansSC%5Bwght%5D.ttf'),
    'RobotoMono': ('robotomono', 'RobotoMono%5Bwght%5D.ttf'),
}
for name, (folder, filename) in FONTS.items():
    source = SOURCE / f'{name}.ttf'
    base = f'https://raw.githubusercontent.com/google/fonts/main/ofl/{folder}/'
    if not source.exists():
        urllib.request.urlretrieve(base + filename, source)
    license_path = ASSETS / f'OFL-{name}.txt'
    if not license_path.exists():
        urllib.request.urlretrieve(base + 'OFL.txt', license_path)

# Include source text plus Chinese Material accessibility/dialog strings.
corpus = ''.join(path.read_text() for path in (ROOT / 'lib').rglob('*.dart'))
sdk = Path(os.environ.get('FLUTTER_ROOT', str(ROOT / '.fvm/flutter_sdk')))
localization = sdk / 'packages/flutter_localizations/lib/src/l10n/generated_material_localizations.dart'
if localization.exists():
    source = localization.read_text()
    corpus += source.split('class MaterialLocalizationZh extends', 1)[1].split(
        'class MaterialLocalizationZhHans extends', 1)[0]
# City, news, and public release names arrive at runtime. Bundle common CJK
# rather than requiring a remote fallback font for everyday Chinese content.
corpus += ''.join(chr(code) for code in range(0x4E00, 0xA000))
corpus += ''.join(chr(code) for code in range(0x3000, 0x3040))
corpus += ''.join(chr(code) for code in range(32, 127)) + '\u00a0\u2026\u2192\u00b7'


def build_font(source, destination, family, text):
    font = instantiateVariableFont(TTFont(source), {'wght': 400}, inplace=True)
    options = subset.Options()
    options.name_IDs = ['*']
    options.name_legacy = True
    options.name_languages = ['*']
    cutter = subset.Subsetter(options=options)
    cutter.populate(text=text)
    cutter.subset(font)
    # Modified subsets use new family names, preserving license/copyright records.
    for record in font['name'].names:
        names = {1: family, 2: 'Regular', 3: family + '-Regular-1.0',
                 4: family + ' Regular', 6: family + '-Regular', 16: family, 17: 'Regular'}
        if record.nameID in names:
            record.string = names[record.nameID].encode(record.getEncoding())
    font.save(destination)
    print(f'{destination.relative_to(ROOT)}: {destination.stat().st_size:,} bytes')


build_font(SOURCE / 'NotoSansSC.ttf', ASSETS / 'ShikeSans-Regular.ttf', 'ShikeSans', corpus)
build_font(SOURCE / 'RobotoMono.ttf', ASSETS / 'RobotoMono-Regular.ttf', 'ShikeDigits',
           '0123456789:.AMP ')


def icon(size, maskable=False):
    scale = 4
    s = size * scale
    image = Image.new('RGB', (s, s), '#08090B')
    draw = ImageDraw.Draw(image)
    radius = s * (.27 if maskable else .32)
    cx = cy = s / 2
    stroke = max(2, round(s * .035))
    draw.ellipse((cx - radius, cy - radius, cx + radius, cy + radius),
                 outline='#E8E9EB', width=stroke)
    draw.line((cx, cy - radius * .55, cx, cy, cx + radius * .42, cy),
              fill='#E8E9EB', width=stroke)
    r = stroke / 2
    for x, y in [(cx, cy), (cx, cy - radius * .55), (cx + radius * .42, cy)]:
        draw.ellipse((x-r, y-r, x+r, y+r), fill='#E8E9EB')
    return image.resize((size, size), Image.Resampling.LANCZOS)


icons = ROOT / 'web/icons'
icons.mkdir(exist_ok=True)
for size in [192, 512]:
    icon(size).save(icons / f'Icon-{size}.png')
    icon(size, True).save(icons / f'Icon-maskable-{size}.png')
icon(180).save(icons / 'apple-touch-icon.png')
icon(32).save(ROOT / 'web/favicon.png')
mac_icons = ROOT / 'macos/Runner/Assets.xcassets/AppIcon.appiconset'
if mac_icons.exists():
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        icon(size).save(mac_icons / f'app_icon_{size}.png')
print('Generated 此刻 app icons.')
