# カード画像の自動生成(pokecardmaker.net)

- 環境「megapoke」で動かす(pokecardmaker.net / api.pokecardmaker.net / cdn.customcardmaker.net を許可済み)
- 日本語フォント: `apt-get install -y fonts-noto-cjk` と、fontconfigで sans-serif → Noto Sans CJK JP を優先にする
- 使い方: `node tools/cardmaker/make_card.js カード.json 出力.png`(JSONをサイトにImport → Download 1x)
- JSONの書き方は `sample_roi.json` を参照。Era=Pocket(`baseSetId:"5"`)
  - `typeId`: 1草 3水 5超 7悪(他は未確認) / `retreatTypeId:"11"`=無色
  - `dexStats` に図鑑の行をそのまま書く(例 `NO.0001  ちょうりメガモン`)
  - 弱点は `weaknessModifier:"plus"` + `weaknessAmount:"20"`
  - ワザの説明は自動で折り返さないので `\n` で改行
- 未対応: イラスト画像の入れ方(`images`)、説明文中のエネルギーアイコン、ex・怪化(Stage1)、レアリティ記号の切り替え

## カードを1枚作る流れ(2026-11 確立)
1. `sample_basic.json`(たね)か `sample_stage1.json`(怪化)をコピーして、名前・HP・ワザ・図鑑の行・フレーバーを書き換える
   - `subtypeId`: `"1"`=たね / `"2"`=怪化(STAGE1)。怪化は `prevolveName` に怪化前の名前
   - 特性は `moves` に `isAbility:true` で入れる。エネルギーは `energyCost:[{typeId, amount}]`(超=`"5"`、無色=`"11"`)
   - レアリティの◇は `customRarityIconImage.src` の画像。◇3は◇1の画像を横に3つ並べたものを入れてある(`sample_stage1.json`)
2. `node tools/cardmaker/make_card.js カード.json 枠.png` で、枠+文字だけのカードを作る(絵の窓は白)
3. `python3 tools/cardmaker/compose.py 枠.png 絵.png cards/名前.webp [--prev 怪化前の絵.png --prevname 怪化前の名前] [--bg 内側の色 外側の色]` で絵をはめ込む
   - サイトの画像アップロードは自動操作できなかったので、絵はこのスクリプトで入れる
   - 透明な背景の絵は `--bg` の2色でぼかした背景を敷く
4. `megapoke.html` の `CARDS` に `image:'cards/名前.webp'`(Supabaseに上げなくていい。リポジトリの `cards/` から配信される)、`PRINTS` に刷りを足す
