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
