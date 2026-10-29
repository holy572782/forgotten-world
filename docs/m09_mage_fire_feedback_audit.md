# 魔導士の床面魔法陣・炎命中演出（2026-10-29、ADR-044）

## 目的・開始時・境界

ユーザー指定：魔法陣を魔導士の下へ表示し、本体の上へ出さない。RPGツクールeffectsの炎全体3の魔法陣に近づけ、詠唱音はMagic1／ピッチ90%。炎弾が主人公へ命中したら炎単体1とFire2、防御中も同じ演出とダメージアニメーションを再生する。

開始時はADR-043までの実装と進捗が一致。未追跡のユーザー提供 `RPGツクールMZeffects/` と、エディターが生成する `addons/effekseer/bin/windows/~libeffekseer.x86_64.dll` が存在した。両者を削除／置換していない。Issueは未作成。対象は表示・音声・主人公の該当する被弾表示のみ。

炎弾の速度5m/s・最大距離13.2m／半径0.2m・ダメージ10・明示MAGICと通常Guard貫通、敵の詠唱／発射／回復・射程内停止、雑兵・主人公の操作／コンボ／防御／帰還と通常物理被弾は維持する。M09基本戦闘完了・既存追加改善のF5待ち・M10別指示待ちを維持する。

## 素材と床面表示

提供ファイルのFireAll3＝炎全体3、FireOne1＝炎単体1として、実際の編集データをEffekseer 1.80.5のCore DLLで読み取った。FireAll3のHexCircleDownと同じHexCircle.pngを無加工コピーし、上へ浮く層を除いた床面保持用efkefcを制作。以前のオリジナルefkefc／SVG／XMLは保持する。編集情報付きefkefc・XML・再生成手順は `assets/effects/mage_circle_fire/`、`assets/source/effects/mage_circle_fire/`、`tools/prepare_mage_fire_effects.ps1`。

魔法陣は専用の透明SubViewport（256×256・独立World3D・真上からの正投影）内でNative Effekseerを再生し、その結果を実地面のPlaneMeshへ投影する。Nativeの粒子ソートを本体から分離し、通常の床面深度・描画優先度-10、影OFF／衝突なしで本体の下へ表示する。アクティブな詠唱中／発射fadeの間だけViewportを更新し、終了／地面未検出／非表示／HP0で投影・Nativeを停止する。

Game側の既存Circle Enabled／Diameter2.8m／Y回転0.25rad/s／Release Fade0.12秒を再利用。魔導士ResourceだけGround Offset=0.01m、Circle Color=(1,0.62,0.28,1)、Circle Effect Is Floor=true。床面に焼き込んだX=90度を持つデータなのでEmitter自体は回転しない。旧XY制作データはCircle Effect Is Floor=falseで読める。Effect=nullは既存のShader表示へ戻す。

魔導士の既存AttackWarningにMagic1の無加工コピー `mz_magic1.ogg` を割当、Pitch Scale=0.9。実WINDUPへの遷移で1回だけ鳴る。魔導士の旧Fire1と重ねない。雑兵のFire1・他SEは維持。

## 炎の命中と防御中の被弾表示

`assets/effects/mage_fire_hit/fire_one1.efkefc` は提供FireOne1原本とバイト一致。Fog／Particle100／ParticleAlphaの依存PNGも同じ相対配置で無加工コピー。MagicVisualSettingsにHit Effect／Scale（0.06）／Sound／Volume（-12dB）／Pitch（1.0）を持たせ、Fire2を割り当てる。

既存Projectile._consumeの一度だけの消費後、既存Health.damageの実HP減少を確認したMAGIC弾だけが命中演出を作る。弾から独立した兄弟Node3Dで、命中した主人公の位置＋0.7mにNative EffectとFire2を1回再生する。弾の解放では途切れず、Nativeの自然終了／音声完走後に解放。差替素材がループしても表示は6秒で停止し、音声は自然終了を待つ。シーン終了ではまとめて解放する。壁・射程／寿命終了・被弾不成立・物理矢には出さない。見た目の倍率を衝突へ使用しない。

PlayerDamageVisual.show_magic_hitを、確認済みの魔法弾の被弾後に呼ぶ。この反応中だけGuardでも既存ダメージ画像を3コマ／約0.3秒表示し、終了時には保持中のGuard／盾表示へ戻る。論理Guard・軽減／属性・入力は変更しない。普通の物理被弾は従来どおりGuard中のダメージ表示を抑え、ヒール／resetでは反応許可も解除する。Native Effect／Fire2の内容は通常とGuardで共通。

## 変更・出典管理

- Resource：magic_visual_settings.gd、mage_magic_visual.tres、ranged_practice.tres。
- 接続：mage_cast_visual.gd、practice_projectile.gd、player_damage_visual.gd、新規fire_hit_presentation.gd。
- 素材：新しい床面efkefc／XMLとHexCircle、FireOne1と3依存PNG、Magic1／Fire2のOggコピー。原本・旧制作物・プラグイン配布物は保持。
- 検査：新規mage_fire_feedback.gd、既存mage_magic.gdの新設定と実Native Viewport A/B、enemy_followup.gdの敵別保存ピッチを更新。既存の物理Guard／ダメージ画像の期待値は緩めない。
- 記録：素材台帳、AGENTS、README、ADR-044、システム仕様／検査計画／進捗、本書。以前の監査は履歴として保持し、冒頭から本書へ案内する。

ユーザー提供のRPGツクールMZ素材として出典と未確認の許諾状態を台帳に記録。作者・Godotでの利用／再配布条件を承認済みとは扱わず、新しいMIT等の許諾を付けない。今回commit／pushは行わない。

## 検証と再現

Godot 4.7.2.stable.official.ed1daf0bf／Compatibility／GTX 1080。開いているユーザーエディターとNative DLLの一時コピーが競合したため、`.godot/mage_fire_validation/` に同じソース・必要なWindows DLLを複製して検査した。ユーザーのエディターを終了させず、配布DLLも変更していない。`tools/validate_mage_fire.ps1` で複製・初回import・新検査を再現できる。検査プロセスのAPPDATA／LOCALAPPDATAはworkspace内へ分離する。

初回のNative直接描画は特定方向で本体との重なりが残ったため、床面への投影へ変更。画像比較はNative Emitterを明示hideし、Viewport反映と既存カメラ／壁fadeが落ち着いてから取得する。身体判定は投影した元画像の不透明内部かつ、基準画像でも元の色が実際に描画される画素のみを使い、床・遮蔽面・輪郭の別画素を身体と誤認しない。4方向の本体サンプルは各719〜1051点で、魔法陣による上書きは0点。

新規検査は選択素材のhash、Magic1単発／0.9pitch、床面・4方向の実描画／身体非重複、実炎弾の1回被弾、通常／Guardの同じNative FireOne1／Fire2／ダメージ画像、Guard維持と元画像復帰、壁での不発、弾解放後の完走／掃除を検査する。既存mage_magicと被弾画像／敵戦闘も回帰する。最終結果は末尾に追記する。

通常のPowerShell再現例（Godotは1プロセスずつ。開いたエディターと競合する場合は上記検証用コピーを使用）：

```powershell
$godotExe = 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --editor --import
& $godotExe --path . --script res://tests/mage_fire_feedback.gd
& $godotExe --path . --script res://tests/mage_fire_feedback.gd -- --fps30
& $godotExe --path . --script res://tests/mage_magic.gd
& $godotExe --path . --script res://tests/player_damage_visual.gd
```

## 最終結果

検証用コピーで11条件すべてPASS・終了0。最終ログにScript／Parse／Shader／Resourceエラー・警告なし。

| 検査 | 結果 |
|---|---|
| mage_fire_feedback 60／30fps上限 | 各33項目PASS |
| mage_magic 60／30fps上限 | 124／84項目PASS |
| mage_magic --reload | PASS |
| player_damage_visual | 139項目PASS、通常物理Guardの表示抑止も維持 |
| enemy_followup | 221項目PASS |
| m09_startup | PASS |
| m08_defense | PASS、方向帰還／Guard／ストック・命中／カメラ／reset |
| enemy_sword_combat | 445項目PASS |
| effekseer_integration | 13項目PASS |

既存enemy_followupの射程外7m fixtureはADR-042以前の全停止期待が残っていたため、射程内5mで近接用歩行の非適用を検証するよう補正。射程外で再接近する仕様とmage_magicの検査は維持し、敵AIの実装を変更していない。

検査終了時には競合するGodotプロセスがなくなっていたため、**元のプロジェクトでも最終editor import・新規実描画60fps検査を実行し、33項目PASS・終了0**。両ログにエラー／警告なし。`git diff --check` 合格。元プロジェクトの `.godot/mage_fire_floor.png`／`mage_fire_hit_guard_true.png`／`mage_fire_flame_guard_true.png` 等を目視し、ログは `.godot/fire_final_*`、検証用コピーの画像／計測は `.godot/mage_fire_validation/.godot/` に保持する（Git対象外）。

## F5での確認（ユーザー未実行）

1. F8で実行を止め、必要に応じGodotを開き直してインポートを待つ。F5→「遠距離敵」。FireAll3に近い橙色の魔法陣が魔導士の足元の下に表示され、Q/Eでも本体を塗らないこと。
2. 詠唱開始のMagic1を90%ピッチで聴き、発射時の短いfade・中断／撃破／モード変更で残らないことを確認する。
3. 通常と右クリック／I防御中のそれぞれで炎弾を受け、同じ炎単体1とFire2、主人公のダメージ3コマが出ること。防御保持中は約0.3秒後に盾表示へ戻ること。通常魔法は従来どおりHP10減少。
4. 壁に当たった弾には主人公の演出が出ないこと。雑兵へ切り替え、物理Guard半減／Guard姿勢維持・左攻撃／J・連撃・方向帰還・Space／Q/E、既存SEが従来どおりであること。

音量・色／サイズ・Native Hit倍率はMage Magic Visual／Ranged PracticeのInspectorで調整・保存できる。最終的な見た目・聴感／操作感、任意の複雑地形・実機パッド・他OS／エクスポート・長時間負荷は未確認。M09基本戦闘完了と今回のF5確認待ちは区別する。
