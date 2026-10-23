# M09 編集済み鉄の剣・武器別エフェクト実装記録

2026-10-23、ADR-021。**M09追加改善、ユーザーF5／F6の受入確認待ち。** M08試作範囲完了・既存残件・M10別指示待ちを維持し、新しいマイルストーンは作成しない。

## 着手・素材の確定

開始時はmain、HEAD `7a422d13aa102d2f65d027e776118cfb06a287a0`。元の剣PNG、ASSET_REGISTERとDEVELOPMENT_STATUS、先行のAseprite／合成PNG／Lua／制作記録、白い斬撃PNGが未コミット。進捗と実物は一致し、それらを保持して今回の実装を追加した。Issue／PR／commit／pushは作成・実行していない。

「武器エフェクト」はフォルダで、内部の実画像は「片手剣エフェクト白.png」1枚だった。ユーザーへ確認し、**「白い斬撃を使用し、武器付随エフェクトは設定枠のみ用意する」**との回答を受領。白をSlashEffectで1回だけ使い、WeaponEffectは無効枠のみとする。画像を推測生成したり、同じ白を本番で2重表示したりしない。

| 素材 | 原本 | ゲーム用コピー | 構成・透明領域 |
|---|---|---|---|
| 編集済み鉄の剣 | `画像フォルダ/武器/鉄の剣.png` | `assets/sprites/weapons/iron_sword_attack.png` | PNG／RGBA、336×448、112px×横3・縦4。4032可視画素（各コマ336）、146496完全透明画素、alphaは0／255 |
| 白い斬撃 | `画像フォルダ/武器/武器エフェクト/片手剣エフェクト白.png` | `assets/sprites/weapons/one_handed_sword_white_slash.png` | PNG／RGBA、336×448、112px×横3・縦4。4712半透明画素、145816完全透明画素、非ゼロalphaは32〜229の複数値 |

両画像とも行順は既存の下・左・右・上、列0／1／2。実画像・先行制作記録・剣と弧の位置関係を照合した。白の可視領域は各112px枠内、透明キャンバスはトリミングしない。更新剣は以前と同サイズだが、振り始めなどのコマ配置が変わっている。画像補正・リサイズ・描き直しは行っていない。

- 剣SHA256：`83a197fd6a9c890ec505227dbd84a2de02ac61e83e103a21790e5916ca7c4135`。
- 白SHA256：`dba350d5189dea0e6d29b0e79eb0cb3f6b205fa26896bdc38b623c9809894d18`。
- 無損失インポート、fix_alpha_border=false、nearest、mipmapなし、自動3D圧縮なし。全RGBAと12切り出し矩形の一致を検査する。
- `assets/export/weapons/iron_sword_slash.png`は剣＋弧の合成版なので本編から参照しない。`assets/source/weapons/iron_sword_slash.aseprite`、制作Lua、`docs/iron_sword_slash_asset.md`も変更せず保持する。

## 論理レイヤーと同期

| 役割 | 実ノード／管理先 | 今回の処理 |
|---|---|---|
| BodySprite | Player/AnimatedSprite3D | 本体48pxと既存アニメーションを維持 |
| WeaponSprite | Player/WeaponSwing | 編集済み112pxシートへ更新。旧画像との重複ノードなし |
| WeaponEffect | Player/WeaponEffect | 独立ノード・設定枠。画像未指定／enabled=false |
| SlashEffect | Player/SlashEffect | 白い斬撃を独立表示 |
| ShieldSprite | 既存PlayerSprite＋ShieldVisualData | Guard画像へ切り替える現在の方式を維持。今回新しい盾ノードへ作り替えない |

本体のanimation／frame／frame_progressから相対コマ時間を合算し、攻撃全体の0〜1の進行を得る。エフェクト側の開始／終了phaseと速度を適用し、その進行に対応するSpriteFramesのコマとコマ内進行を直接指定する。SpriteFramesの各コマdurationは相対比率として使い、独自の秒タイマーやplayによる時計は持たない。アニメーション名は本体のattack_down/left/right/upをそのまま使用する。

同じ3コマ・同じ比率なら本体と同じコマになり、5コマや不均等durationでも指定期間に合わせられる。武器の攻撃速度が変わっても本体時計へ追従する。連撃の各実斬撃開始でphase0から再開する。攻撃完了通知で非表示にし、各描画tickにも本体の攻撃中・可視・戦闘Attack状態を検査する。Guard、Return、被弾による本体置換、撃破後の待機、cancel／reset、設定欠落・不正Atlasで残像を出さない。

## 位置・半透明・奥行き

本体と同じtransform、billboard、pixel_size=0.0375、offset(0,23)を継承し、追加の方向offsetだけをピクセルで加える。112pxを48pxへ正規化しない。SubViewportは追加せず、直前の独立Sprite3D方式を利用する。

所有者カプセル深度・床補正・画素ごとの敵／壁判定を`actor_attachment_depth.gdshaderinc`へ共通化した。既存の不透明剣はalpha<0.5のdiscardを維持。エフェクト専用Shaderは原画像のALPHAを通常合成し、alpha0だけdiscard、depth_draw_neverで他の層の深度を汚さない。no_depth_test=falseは維持し、壁を無条件に無視する実装ではない。

WeaponSwingの地形ray判定を同じ描画tickで共有する。剣の深度bias=0.000002、WeaponEffect=0.000003、SlashEffect=0.000004。透明効果同士の順はMaterial.render_priority=0／1で安定させるが、3D壁・敵の遮蔽は引き続き深度に従う。盾・本体Shader・カメラの既存フェードは変更しない。

## 差し替え・将来の武器追加

1. WeaponDataのattack_visual（WeaponAttackVisualData）を武器別に作成／複製。武器本体のattack_framesは従来の3コマ×4方向を指定する。
2. 武器付随／斬撃は別々のWeaponEffectDataをweapon_effect／slash_effectへ指定。framesにはattack_down/left/right/upのSpriteFramesを設定する。コマ数は任意。シートを切り出したAtlasTexture（単独画像なら全領域のAtlasTextureでも可）を使う。
3. enabled、enabled_directions、offset_down/left/right/up（px、+X右・+Y上）、start_phase／end_phase（0〜1）、playback_speedを設定する。現在の白は全方向・0〜1・速度1・offset0。武器付随はenabled=false／frames未指定。
4. 速度1は指定期間内で全コマを一度再生。速度2は前半で終了して消え、速度0.5は途中までゆっくり進めても期間末で消える。開始終了が不正なら非表示。ループ・自動延長はしない。
5. 新武器の攻撃回数・攻撃速度・命中範囲は既存WeaponDataで別管理。画像寸法・効果の見える範囲から当たり判定を作らない。今回は新武器・装備UI・新しい回避機能を追加しない。

## 変更ファイル

- コード：`scripts/player/weapon_effect_data.gd`（新）、`weapon_effect_visual.gd`（新）、`weapon_attack_visual_data.gd`、`weapon_swing_visual.gd`。
- 描画：`assets/shaders/actor_attachment_effect.gdshader`（新）、`actor_attachment_depth.gdshaderinc`（新）、`actor_attachment_depth.gdshader`、`scenes/player/player.tscn`。
- データ／素材：更新`assets/sprites/weapons/iron_sword_attack.png`、新`one_handed_sword_white_slash.png`とimport／frames、`resources/weapons/iron_sword_slash_effect.tres`（新）、`iron_sword_visual.tres`。
- 検査：新`tests/weapon_effects.gd`、`tests/weapon_depth.gd`の独立レイヤーfixture／効果モード、`tests/weapon_sweep.gd`のPNG一致期待。Godot生成UIDを含む。
- 記録：README、ASSET_REGISTER、ADR-021、システム仕様、実装計画、テスト計画、戦闘仕様、DEVELOPMENT_STATUS、本書。
- TargetDash・Controller・PlayerSprite・DamageVisual・combat共通部・敵AI・カメラ、本体PNG／Frames・盾、攻撃／防御設定・初期武器数値は変更しない。既存のHit処理と演出は接続しない。

## 自動検査・実描画

Godot `4.7.2.stable.official.ed1daf0bf`／Windows、物理60Hz、実描画1152×720・Compatibility／OpenGL3.3／GTX1080。フリーズ履歴を考慮し1プロセスずつ実行。最終対応OSや性能保証を確定する記録ではない。

```powershell
$godotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --script res://tests/weapon_effects.gd --log-file .godot/m09_effects_reg_weapon_effects.log
& $godotExe --path . --script res://tests/weapon_effects.gd --log-file .godot/m09_effects_render60.log -- --capture
& $godotExe --path . --script res://tests/weapon_effects.gd --log-file .godot/m09_effects_render30.log -- --fps30 --capture
& $godotExe --path . --script res://tests/weapon_depth.gd --log-file .godot/m09_effects_reg_depth_weapon_final.log -- --capture
& $godotExe --path . --script res://tests/weapon_depth.gd --log-file .godot/m09_effects_reg_depth_slash_final.log -- --effect --capture
```

- 新weapon_effects：ヘッドレス2260、実描画60上限2160／30上限1176 assertionsでPASS・終了0。件数は観測tick数で変動する。4方向の全3コマとQ/E、速度0.5／2、5コマ・不均等duration、独立2枠と方向offset、開始終了・方向別有効化、3／5連撃、命中コマ・消費、撃破後待機・被弾・Guard・帰還・cancel・参照欠落の消去を検査。
- WeaponEffectの2枠同時確認では白の参照を検査用に複製しただけで、本番には追加画像や二重表示を接続していない。無効枠には未初期化の位置を要求せず、表示中の層だけ本体倍率・位置を検査する。
- 更新剣と半透明斬撃はweapon_depth各37 assertions、PASS・終了0。他層をfixture内で無効にし、全12コマの床あり／なしの差分画素集合が完全一致。全面不透明壁と近接壁では0画素、部分壁は剣1059→415／弧1522→1361、手前カプセルは325／1216、奥カプセルは各参照と一致。半透明壁・足元だけの敵遮蔽・段差／崖・4Yaw・診断no_depthの復元を確認。
- 更新画像では低い剣がdownの第2コマへ移ったため、壁／敵の個別fixtureをそのコマへ変更。全12コマ比較は維持。weapon_sweepは旧PNGの固定SHAから最新原本一致へ変更しただけで、攻撃の期待値は維持した。
- 描画画像`iron_sword_effect_<yaw>_<frame>_60／30.png`で剣・白い弧・中心・透過、`effect_depth_*.png`で床／壁／敵を目視。ログと結果はGit除外の`.godot/m09_effects_*.log`／`m09_effects_results.json`／`m09_effects_reg_results.json`。
- 初期のフレーム定義生成でファイル名を置換し過ぎた参照誤り、Shader helperから組込み行列を直接読めないコンパイルエラーを修正。行列をfragmentから渡して共通化した。最初の新検査の「無効枠にも初期位置を要求する」期待も修正した。これらの初回ログは最終合格に含めない。

### 関連回帰・最終点検

- 既存14種類（weapon_depth、iron_sword_animation、weapon_sweep、m07_combo／m07_chain、m08_defense／m08_guard_sprite、player_damage_visual、m09_enemy_dash／m09_enemy_combat、defeat_return_timing、m04_occlusion／m04_shadows、m09_startup）がPASS・終了0。新weapon_effectsと合わせ15種類。weapon_depthは剣／斬撃の2条件で実行し、最終一覧は16実行分。M00からの全スイート再実行を主張する結果ではない。
- 撃破帰還はエフェクト接続状態でdefeat_return_timingが1869 assertions PASS。通常3段と1／2／最終撃で倒した場合の初段開始→Return開始はすべて74tick。5回武器は通常／途中撃破とも128tickで、元のタイミングを維持。元対象の即時free／queue_freeと別の生存予約への連撃も含む。
- 新規表示検査、既存回帰、両層深度、最終editor importにSCRIPT ERROR／Parse Error／SHADER ERRORなし。証明書ストア、GLES3キャッシュ保存、editor設定保存の環境ERRORは別記する。M04の意図したCamera safety警告は保持する。
- 最終headless editor importは終了0、新規Script／Shader／include／検査のUIDを生成。git diff --check成功。TargetDash・Controller・PlayerSprite・DamageVisual・combat共通部・敵AI・カメラ・本体PNG／Frames・盾・攻撃／防御設定・初期武器数値はHEADと差分なし。
- 開始時に記録した原本PNG／import・Aseprite／合成PNG・Lua／制作記録はSHA256一致を再確認。既存未コミットの素材制作を上書きしていない。ゲーム用2PNGは原本とバイト一致。新しい権利承認・作者情報は補作しない。検証用Godotは終了済み、commit／push未実行。

## 手動12項目の確認

1. F8→F5、J／クリックで編集済み剣と白い斬撃を確認。Q/Eで4方向・各3コマ、攻撃中回転、手元・中心・同倍率を確認する。武器付随枠はユーザー指定により非表示が正しい。
2. 攻撃を予約して連撃し、各回の同期と終了後の消去を確認。方向入力帰還・I防御・被弾でも効果が残らないこと。
3. 敵の近く・壁際／壁の背後・段差／崖で確認。不透明壁には隠れ、既存フェードでは本体とともに見え、床で欠けないこと。
4. 静止敵をHP10／20／30にしてから倒し、従来の1／2撃目後の待機・最終撃後の帰還、生存予約への連撃を確認。F6のweapon_sweep_trialで前方3体へ各10ダメージ・1消費・元位置帰還を確認する。

ユーザーのこの修正版でのF5／F6操作と見た目・手元の受入は未実行。実機パッド、長時間性能、複雑地形、多数／大型敵、任意の透明Shaderや複雑な交差メッシュは従来の未検証として保持する。工程を完了扱いにせずM09検証待ち。
