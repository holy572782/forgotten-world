# 魔導士の詠唱魔法陣 — Effekseer

オリジナルの幾何学模様を持つEffekseer 1.80.5用エフェクト。`mage_circle.efkefc` は制作情報（EDIT）と実行データを含み、Effekseerで開いて編集できる。依存する `textures/` を同じ相対配置で保持する。

- 外周：二重円・16個の独自の線記号・4個の菱形。
- 内側：逆方向に回転する幾何学の封印と中央の小円。
- 白いテクスチャを使用し、ゲーム側の `Circle Color` で既存の赤色に着色。
- 直径2.8m、地面から0.035m、外周0.25rad/sは既存設定を継承。内周はEffekseer内で毎フレーム-0.35度（基準60fps）回転。
- ネイティブの固定Sprite 2枚、Blend、深度テストON・深度書込OFF、7フレームの出現。Light／歪み／音／GPU粒子／当たり判定は使用しない。
- 制作座標はXY。ゲーム側でEffekseerEmitter3DをX=-90度として水平XZへ配置。外側のNode3DをY回転するため地面への配置を保つ。
- 各Spriteは1個・寿命60000フレームの保持用。ゲーム側で既存WINDUP／発射後0.12秒fadeを管理し、終了／中断／死亡で明示stopする。Autofree／AutoplayはOFF。直接配置して再生する場合も所有者側で停止する。

制作元SVG／XMLは `assets/source/effects/mage_circle/`。`tools/create_mage_circle.ps1` がSVG生成→PNG化→公式Effekseer CLI保存を行う。外部の画像・文字フォント・既存作品の固有記号は使用していない。プロジェクトの最終ライセンスは未選定。素材台帳と `docs/m09_mage_effekseer_circle_audit.md` を参照。
