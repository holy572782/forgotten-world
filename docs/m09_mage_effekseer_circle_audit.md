# 魔導士のEffekseer魔法陣（2026-10-29、ADR-043）

> ADR-044更新：ユーザー指定によりFireAll3参照の床面投影へ変更し、Magic1／pitch0.9とFireOne1／Fire2の実命中・Guard中ダメージ表示を追加。以下は最初の制作履歴。旧データ／原本は保持し、最新の設定と検査は [炎命中演出記録](m09_mage_fire_feedback_audit.md) を優先する。

## 目的と対象

ユーザーの「魔導士の足元に魔法使用時に出る魔法陣をEffekseerで作成」依頼。着手時git statusはクリーン。ローカルではADR-042の標準Mesh／Shader魔法陣・炎弾／MAGIC属性・射程内停止まで実装されており、最新進捗と一致した。

今回は魔法陣の制作と表示先だけをEffekseerへ移す。受入条件はネイティブefkefcと編集元を保持すること、実WINDUPの開始・発射fade・中断／HP0で停止、足元配置・回転／サイズ／色調整、既存の炎弾・Guard貫通／物理軽減・攻撃タイミング／AI・主人公の戦闘を維持すること。Issueは未作成。

M09は完了（試作範囲・基本戦闘）を維持。今回の見た目のユーザーF5受入は未実行、既存追加改善のF5待ちも維持。M10は別指示待ち。

## 制作物と同期

`assets/effects/mage_circle/mage_circle.efkefc` に、外側の二重円・16個の独自線記号／4個の菱形と、逆回転する内側の幾何学模様を作成。外部フォント・画像・既存作品の固有意匠は使用していない。ベクターをGodotで512×512透過PNGへラスター化し、固定Sprite 2枚を公式Effekseer 1.80.5で保存した。元SVGと管理可能なXML `.efkproj`、再生成スクリプトも保持する。efkefc自体も制作情報を含み、Effekseerで開いて編集できる。

`MagicVisualSettings.circle_effect` へEffekseerEffectを追加し、魔導士の `mage_magic_visual.tres` に割当。従来のcircle_enabled／diameter2.8m／赤色／地面offset0.035m／回転0.25rad/s／発射fade0.12秒を再利用。nullの場合は元のMesh／Shaderへ戻るため、旧設定を破壊しない。炎弾の表示・属性・速度／距離・衝突は変更していない。

既存の `attack_warning_started`／`attack_started` とWINDUPのelapsedを表示ノードが読む。Effekseerの7フレームの出現と内周の回転は表示だけの動作。攻撃の新しい時計／命中通知／HP処理は追加しない。各Spriteは1個・保持用の長い寿命で、ゲーム側から終了／中断／無効化・非表示・死亡時にstopする。発射時の0.12秒は元のrelease時計でalphaを減らす。敵の子ノードとしてシーン終了／敵解放で一緒に解放する。Shaderとの二重表示はしない。

テクスチャの制作平面XYをEmitterのX=-90度でXZに変換し、毎tickで実地面を検索して配置。地面が見つからない場合は停止・非表示。Blend／ZTest ON／ZWrite OFFで、壁・床／敵本体の通常深度を保持し、Light・影・衝突・音・歪み・GPU粒子を追加しない。外側は既存Y回転、内側はネイティブで-0.35度／フレーム（60fps基準）の追加回転。

## 編集とF5確認

1. Godotで初回インポートを待ち、F5 →「遠距離敵」。魔導士の詠唱時、足元に赤い魔法陣が現れ、外側と内側が逆方向に回ること。
2. 炎弾の発射時に約0.12秒で消え、次の詠唱で再び現れること。予告中の撃破／モード切替で残らないこと。
3. `resources/enemies/mage_magic_visual.tres` のCircle Effect／Diameter／Color／Ground Offset／Rotation Speed／Release Fade Secondsで調整・保存できること。Effect=nullなら従来表示へ戻る。
4. 既存の炎弾／赤点滅／Fire1・通常Guard貫通、雑兵の物理Guard・主人公の左攻撃／J／連撃・方向帰還／Space／Q/Eを確認する。

上記ユーザー操作は未実行。Effekseerでのデザイン編集は `.efkefc` を開き、依存texturesを同じ位置に保持する。Godotの「Open in Effekseer」を使う場合はEditor Pathに実際のツールを指定する。作業用ツールの取得先は [公式1.80.5](https://github.com/effekseer/Effekseer/releases/tag/1805)。制作ツールのZIPと展開先は `.godot/effekseer_authoring/`（Git対象外）であり、配布ゲームには含めない。

再生成（プロジェクト直下PowerShell。手動編集後は別名保存を先に行う）：

```powershell
./tools/create_mage_circle.ps1 -EffekseerExe '実際のEffekseer1.80.5/Tool/bin/Effekseer.exe' -GodotExe '実際のGodot.exe'
```

XML／SVG／PNG／efkefcを再生成する。公式CLIの `-cui -in -o` を使用し、生成物のEFKEヘッダーとGodotのインポート／実描画で有効性を確認する。CLI起動はGUIサブシステムなのでStart-Process -Waitで完了を待つ。初回は待機不足のため出力存在確認が先に走ったが、待機を追加して解消した。

## 検証

環境：Godot 4.7.2.stable.official.ed1daf0bf、Compatibility／GTX 1080、物理60Hz。実施したコマンドと最終結果は本書の末尾に記録する。検査中だけAPPDATA／LOCALAPPDATAを `.godot/mage_runtime_appdata` に分離し、ユーザーの個人設定を変更しない。

検査は `tests/mage_magic.gd` の60／30fps上限・別プロセスreloadに、実NativeEffect再生、旧Shaderの非表示、native終了／中断／HP0停止、nullによる旧表示、復帰時の二重表示なし、設定／2テクスチャ依存の再読込を追加。既存の4カメラ方向A/B実画像・炎弾／MAGIC・Guard／移動安全性の期待値は維持する。

再現例：

```powershell
$godotExe = 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --editor --import
& $godotExe --path . --script res://tests/mage_magic.gd
& $godotExe --path . --script res://tests/mage_magic.gd -- --fps30
& $godotExe --path . --script res://tests/mage_magic.gd -- --reload
& $godotExe --path . --script res://tests/m09_startup.gd
& $godotExe --path . --script res://tests/enemy_sword_combat.gd
& $godotExe --path . --script res://tests/effekseer_integration.gd
```

GPU粒子・他OS／エクスポート、実機パッド・長時間性能・任意の複雑地形は未検証。制作ツールのGUI操作による編集・保存往復も未実行（公式CLIで保存）。

最終結果（6条件、全PASS・終了0）：

| 検査 | 結果 |
|---|---|
| mage_magic 60fps上限 | 120項目PASS |
| mage_magic 30fps上限 | 84項目PASS |
| mage_magic --reload | PASS、NativeEffectと2テクスチャ依存も保持 |
| m09_startup | PASS、実main／左攻撃／右防御／敵モード切替 |
| enemy_sword_combat | 445項目PASS |
| effekseer_integration | 13項目PASS、描画差分3112サンプル |

最終headless editor importも終了0。6実行ログと最終importにScript／Parse／Shader／Resourceのエラー・警告なし、`git diff --check` 合格。`.godot/mage_effekseer_circle.png` の実ゲーム内表示を目視。ログは `.godot/mage_circle_*`、4方向の画素計測は `.godot/mage_visual_metrics.json`（いずれもGit対象外）。同じ長さの詠唱・発射fadeと既存炎弾の動作を維持し、ユーザーF5受入は未実行。
