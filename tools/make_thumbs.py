#!/usr/bin/env python3
"""Wiki用の軽いカード画像(thumbs/*.webp)を作る。
megapoke.html の中の Supabase 画像URLを全部拾い、まだ無いものだけ幅360pxのWebPにする。
使い方: python3 tools/make_thumbs.py   (新しいカードを足した後に実行してcommit)
元画像は1枚1〜2MBあるので、Wikiの一覧ではこの軽い画像を使う。無ければWikiは元画像を出す。"""
import io, os, re, sys, urllib.request, urllib.parse
from PIL import Image
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
src = open(os.path.join(root, 'megapoke.html'), encoding='utf8').read()
urls = sorted(set(re.findall(r"https://[a-z0-9]+\.supabase\.co/storage/v1/object/public/card-images/[^'\")\s]+", src)))
made = 0
for u in urls:
    name = os.path.splitext(urllib.parse.unquote(u.rsplit('/', 1)[1]))[0]
    out = os.path.join(root, 'thumbs', re.sub(r'[^A-Za-z0-9_-]', '_', name) + '.webp')
    if os.path.exists(out): continue
    try:
        im = Image.open(io.BytesIO(urllib.request.urlopen(u, timeout=60).read())).convert('RGBA')
    except Exception as e:
        print('skip', u, e); continue
    w = 360
    im = im.resize((w, round(im.height * w / im.width)), Image.LANCZOS)
    im.save(out, 'WEBP', quality=82, method=6)
    made += 1; print('made', os.path.relpath(out, root), os.path.getsize(out) // 1024, 'KB')
print(f'{made} new / {len(urls)} urls')
