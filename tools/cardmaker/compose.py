#!/usr/bin/env python3
"""make_card.js で作った枠+文字のカード画像に、絵をはめ込む。
使い方: python3 tools/cardmaker/compose.py 枠.png 絵.png 出力.webp [--prev 怪化前の絵.png --prevname 怪化前の名前] [--bg r,g,b r,g,b]
- 絵の窓(白い四角)を自動で探して、そこに絵を入れる
- 透明な背景の絵は、--bg の2色(内側 外側)でぼかした背景を敷く。不透明な絵は窓いっぱいに入れる
- 怪化カードは左上の八角形に怪化前の絵を入れ、「Evolves from 名前」を「名前から怪化」に書き換える"""
import sys, argparse
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
FONT = '/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc'
ap = argparse.ArgumentParser(); ap.add_argument('card'); ap.add_argument('art'); ap.add_argument('out')
ap.add_argument('--prev'); ap.add_argument('--prevname'); ap.add_argument('--bg', nargs=2, default=['255,244,232', '242,176,196'])
a = ap.parse_args()
def cover(im, w, h):
    r = max(w / im.width, h / im.height); im = im.resize((round(im.width * r), round(im.height * r)), Image.LANCZOS)
    l, t = (im.width - w) // 2, (im.height - h) // 2; return im.crop((l, t, l + w, t + h))
def on_bg(im, w, h, fill=0.97, S=3):
    """透明な背景の絵を、ぼかした2色の背景の上に置く"""
    inner, outer = [np.array([int(v) for v in c.split(',')], dtype='float32') for c in a.bg]
    yy, xx = np.mgrid[0:h * S, 0:w * S]
    d = np.sqrt(((xx - w * S / 2) / (w * S * 0.62)) ** 2 + ((yy - h * S * 0.55) / (h * S * 0.75)) ** 2).clip(0, 1)[..., None]
    g = Image.fromarray((inner * (1 - d) + outer * d).astype('uint8')).convert('RGBA')
    ch = im.crop(im.getbbox()); r = min(h * S * fill / ch.height, w * S * fill / ch.width); ch = ch.resize((round(ch.width * r), round(ch.height * r)), Image.LANCZOS)
    pos = ((g.width - ch.width) // 2, (g.height - ch.height) // 2 + 4)
    glow = Image.new('RGBA', g.size, (0, 0, 0, 0)); glow.paste((255, 255, 255, 150), pos, ch.split()[3]); g.alpha_composite(glow.filter(ImageFilter.GaussianBlur(18)))
    g.alpha_composite(ch, pos); return g.resize((w, h), Image.LANCZOS).convert('RGB')
def fit(im, w, h):
    im = im.convert('RGBA')
    return on_bg(im, w, h) if im.getpixel((3, 3))[3] < 10 else cover(im.convert('RGB'), w, h)
card = Image.open(a.card).convert('RGBA'); px = np.array(card.convert('RGB')); white = px.min(axis=2) >= 250
# 絵の窓 = 中央の白とつながっている範囲(怪化カードは帯の右上にも窓が続くので、十字に探すのでなく塗りつぶしで探す)
wm = Image.fromarray((white * 255).astype('uint8')).copy(); ImageDraw.floodfill(wm, (card.width // 2, 300), 128)
reg = np.array(wm) == 128; ys, xs = np.where(reg); x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
card.paste(fit(Image.open(a.art), x1 - x0, y1 - y0), (x0, y0), Image.fromarray((reg[y0:y1, x0:x1] * 255).astype('uint8')))
if a.prev:
    # 左上の八角形: 中心の色に近い、つながった範囲だけを塗る
    seed = (76, 122); tmp = card.convert('RGB'); ImageDraw.floodfill(tmp, seed, (255, 0, 255), thresh=26)
    m = (np.array(tmp) == np.array([255, 0, 255])).all(axis=2); ys, xs = np.where(m)
    bx0, bx1, by0, by1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    mask = Image.fromarray((m[by0:by1, bx0:bx1] * 255).astype('uint8')).filter(ImageFilter.MinFilter(3))
    pv = Image.open(a.prev).convert('RGBA'); bb = pv.getbbox(); pv = pv.crop((bb[0], bb[1], bb[2], bb[1] + int((bb[3] - bb[1]) * 0.8)))
    card.paste(fit(pv, bx1 - bx0, by1 - by0), (bx0, by0), mask)
    # 「Evolves from 名前」の文字を消して書き直す(帯は横方向に同じ色なので、右のきれいな列の色で塗る)
    px = np.array(card.convert('RGB')); reg = px[96:118, bx1 + 4:bx1 + 150]; dark = reg.max(axis=2) < 125
    cols, rows = np.where(dark.any(axis=0))[0], np.where(dark.any(axis=1))[0]
    tx0, tx1, ty0, ty1 = bx1 + 4 + cols.min(), bx1 + 5 + cols.max(), 96 + rows.min(), 97 + rows.max()
    out = np.array(card); clean = min(tx1 + 30, card.width - 1)
    for y in range(ty0 - 2, ty1 + 2): out[y, tx0 - 2:tx1 + 3] = out[y, clean]
    card = Image.fromarray(out); d = ImageDraw.Draw(card)
    d.text((tx0, (ty0 + ty1) / 2), f'{a.prevname}から怪化', font=ImageFont.truetype(FONT, ty1 - ty0), fill=(35, 35, 35), anchor='lm')
card.save(a.out, quality=90, method=6) if a.out.endswith('.webp') else card.save(a.out)
print('ok', a.out, 'window', (x0, y0, x1, y1))
