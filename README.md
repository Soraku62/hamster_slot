# 🎰 FEVER GACHA

パチスロ風の派手な演出が楽しめるガチャアプリです（Flutter製）。
**授業課題として制作した学生作品です。**

PUSH ボタンを押すとリールが回り、期待度（青 → 緑 → 赤 → 金 → 虹）に応じて
予告・リーチ・フリーズ・ネガポジ・斬撃・雷・炎などの演出が発生します。
結果に応じて景品カード（9種）がランダムに表示されます。

## 遊び方

1. 画面または **PUSH** ボタンをタップ
2. 回転中は下のサブ液晶の絵文字が切り替わります
3. 「押せ!!」が出たらボタンを押す
4. 当たり／ハズレに応じて景品カードがもらえます

## 起動方法

```sh
flutter pub get
flutter run -d chrome   # ブラウザ
flutter run -d macos    # Mac アプリ
```

## 公開（GitHub Pages）

`main` ブランチにソース、`gh-pages` ブランチにビルド済みの Web 版を置く
「Deploy from a branch」方式です。

```sh
./tools/deploy_pages.sh   # ビルドして gh-pages に push
```

GitHub の Settings → Pages → Source を「Deploy from a branch」、
Branch を `gh-pages` / `(root)` にしておきます。

## ファイル構成

| ファイル | 内容 |
|---|---|
| `lib/main.dart` | ゲーム本体（演出の進行・画面構成） |
| `lib/fx.dart` | パーティクルエンジン（炎・雷・斬撃・破片・キラキラ） |
| `lib/text3d.dart` | 立体（3D）文字 |
| `lib/bg.dart` | プログラムで描く背景 7 種 |
| `lib/deco.dart` | 後光・集中線・流れる文字帯・カットインなど |
| `lib/cards.dart` | 景品カードの絵柄と PNG 書き出し |
| `tools/synth_sfx.py` | 効果音を合成する Python スクリプト |
| `tools/deploy_pages.sh` | Web 版をビルドして gh-pages に公開 |

## 素材について

背景・景品カード・効果音はすべて本リポジトリのプログラムで生成したオリジナルです。
実在のメーカー・機種・作品とは一切関係ありません。

- **景品カード** (`assets/cards/`): `lib/cards.dart` で描画し、`EXPORT_CARDS=1` を付けて macOS 版を起動して書き出したもの
- **効果音** (`assets/sfx/`): `tools/synth_sfx.py` で正弦波・ノコギリ波・ノイズから合成したもの
- **フォント** (`assets/fonts/`): いずれも [SIL Open Font License 1.1](https://openfontlicense.org/)。ライセンス全文は同じフォルダの `OFL-*.txt`
  - [Dela Gothic One](https://github.com/syakuzen/DelaGothic) © The Dela Gothic Project Authors
  - [Yuji Boku](https://github.com/Kinutafontfactory/Yuji) © The Yuji Project Authors
  - [Reggae One](https://github.com/fontworks-fonts/Reggae) © The Reggae Project Authors
  - [Rampart One](https://github.com/fontworks-fonts/Rampart) © The Rampart Project Authors

## 注意

- 実際の金銭・景品は一切扱いません。
- 強い光の点滅や画面の明暗反転があります。光過敏の方はご注意ください。
