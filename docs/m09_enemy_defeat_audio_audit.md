> 2026-10-29追記（ADR-039）：飛行の上下運動は減衰する弾みへ調整し、HP0時Cry1を追加。最新設定と検査は [m09_enemy_bounce_cry_audit.md](m09_enemy_bounce_cry_audit.md)。以下の初期単一弧／SE説明は導入時の記録。

# M09完了後：雑兵の共通SEと敵撃破の画面外吹き飛び

2026-10-28／ADR-038。M09基本戦闘完了は維持。今回の演出／聴感はユーザーF5確認待ち、新工程は作成しない。commit／push未実行。

## 開始時の確認

開始HEAD `ae9db4b`、git statusクリーン。AGENTS・開発状況・指定資料08／10／11／12／14、最新M09監査、Player／Enemyの実HP処理・共通武器Feedback・Guard成功・既存Sprite／Shader・Viewport構成を確認。画像／音声素材の新規制作・改名・編集は行わない。

## 雑兵の攻撃SE

| イベント | 実ファイル | 設定元 |
|---|---|---|
| 剣振り | assets/audio/sfx/mz_evasion1.ogg | WeaponData.feedback（共通combat_feedback.tres） |
| 実HP減少を確認した命中 | assets/audio/sfx/mz_slash1.ogg | 同上 |
| 実Guard成功 | assets/audio/sfx/mz_sword2.ogg | 既存DefenseSettings／Player CombatFeedback |
| 予告開始 | assets/audio/sfx/mz_fire1.ogg | 既存EnemySettings／AttackWarning |

新EnemySwordAudioは、既存の敵ATTACK開始通知・共通加重時計・プレイヤーHealth.damage_appliedを観測するだけで、攻撃／HPを追加実行しない。振り始めの設定をsnapshotし、共通のSwing Frame／Percentを物理更新で観測して風切り、実HP減少通知で命中を各1回再生する。描画フレームが極端に短い振りを飛ばしても音を取りこぼさず、別の攻撃時計は作らない。空振り・壁で命中しない場合は命中音なし。Guard成功通知が先に来た振りはSlash1を鳴らさず、プレイヤー側のSword2を利用し二重再生しない。背面からの通常被弾は実HP減少音を使用する。

主人公・雑兵は同じ片手剣のfeedback Resourceを参照する。resources/combat_feedback.tresのSwing／Hit Sound・Volume Db・Pitch Scaleを編集すれば次の振りから両者へ反映。現在の共通初期値はSwing -9dB／pitch1.0、Hit -12dB／pitch1.0。追加の敵専用音量／ピッチ設定は作らない。魔導士はweapon未指定のため新剣音を使わず、従来の弾／Fire1を維持する。音声ファイルと主人公／防御／予告の再生コードは変更していない。

## HP0と表示の分離

- HP0通知で即DEAD、物理更新・移動／攻撃を停止。bodyのcollision_layerとmaskを即0、shapeをdeferred無効化、Targetableを即無効、残弾をconsumed＋破棄する。飛行中の視覚ノードには物理Body／Area／Targetableを持たせない。
- 敵の表示は隠し、同じ親の独立した表示Sceneを生成する。元の敵が先に削除されても飛行は継続。表示終了時は無効な元実体も解放する。シーンリセットや表示の外部破棄も実体を掃除する。開始／終了の二重発動を防止する。
- 元のHealth／ダメージ計算・主人公のコンボ／対象選択／撃破後の残り時間・帰還処理は変更しない。

## 吹き飛びの表示とカメラ

EnemyDefeatSettingsのmode=SCENEからenemy_flyoff.tscnを再生する。CanvasLayerのSprite2Dへ既存の日本語Walk先頭コマを表示し、元のpixel_size・global scale・足元offsetを現在のCamera3Dで投影する。48px固定への拡縮はせず、実Texture寸法を使用。Nearestサンプリングで透過／ドットを保持し、カメラ回転時は従来の4方向行へ合わせる。

最後の実攻撃の固定strike_facingを使用し、取得できない場合は攻撃者→敵の水平方向、さらに不明なら敵の向きを使用する。方向は撃破時に保存し、新しい攻撃者の向きには追従しない。その世界方向を現在のCameraへ投影するため、Q/Eや飛行中の回転でも見えている画面の方向へ自然に飛ぶ。少し上へ浮く弧を加える。

現在のViewportの可視RectとSpriteの完全な表示Rect（offset・scale込み）を比較し、全体が画面外＋余白24pxになってから削除する。速度は設定された最低速度と、目安時間でその画面端へ届く必要速度の大きい方。画面の大きさ・アスペクト・カメラ変更にも計算し直し、固定のワールド座標を端としない。Cameraがなくなった場合も安全期限で解放する。

死亡表示だけを3D地形より前・HUDより後へ合成し、壁の物理／深度で飛行が途中停止・消失しないようにする。存命中の敵・主人公・剣／効果の3D遮蔽はそのまま。致死ダメージの既存白flashを独立Shaderへ引き継ぎ、既存の火花もその寿命のまま使用する。新しい被弾画像・グロー・画面揺れは追加しない。

## Inspectorと将来の差し替え

`resources/enemies/melee_practice.tres`／`ranged_practice.tres` の **Defeat** が共通 `resources/enemies/flyoff_defeat.tres` を参照する。敵ごとに変える場合はDefeat Resourceを複製して別割当する。

| 項目 | 初期値 | 範囲・意味 |
|---|---|---|
| Mode | SCENE | NONEは旧表示、SCENEは指定Sceneを再生 |
| Scene | enemy_flyoff.tscn | 将来の倒れる／消滅Sceneを敵別に差し替え可能 |
| Minimum Fly Speed | 18.0 | 1〜60m/s相当。画面端までに必要なら速める |
| Lift Height | 0.70 | 0〜3m相当の浮き上がり |
| Flyoff Duration | 0.65 | 0.2〜1.5秒の目安。高い最低速度では早く出る |
| Maximum Lifetime | 2.5 | 0.8〜5秒。実行時は目安時間＋0.1秒以上に補正 |
| Offscreen Margin Pixels | 24 | 0〜128pxの画面外余白 |

Resourceを保存すれば再起動後も維持。将来のSceneはconfigure(actor, source, settings)とfinished(reason:String)の契約を実装する。今回は倒れる大型敵／ボスや装備UIを実装しない。Defeat未指定の旧fixtureは従来表示を保ち、HP0の戦闘無効化は共通。

## 変更ファイル

- scripts/enemies/enemy_sword_audio.gd（新規）、practice_enemy.gd、enemy_settings.gd、practice_selector.gd
- scripts/effects/enemy_defeat_settings.gd、enemy_defeat_presentation.gd、enemy_flyoff.gd（新規）
- assets/shaders/defeat_sprite_flash.gdshader（新規、画像を変更しない白flash用コード）
- scenes/effects/enemy_flyoff.tscn、resources/enemies/flyoff_defeat.tres（新規）
- scenes/enemies/practice_enemy.tscn、resources/enemies/melee_practice.tres、ranged_practice.tres
- tests/enemy_defeat_audio.gd（新規）、enemy_sprites.gd、enemy_followup.gd、enemy_tactics.gd
- 新規Script／ShaderのGodot生成UID
- AGENTS.md、docs/08・10・11・12・14、DEVELOPMENT_STATUS、本書

既存画像／音／武器・Motion原本、主人公・Healthの計算／入力、敵の照準／歩行・命中／弾の計算、既存白flash／火花スクリプトは変更しない。

## 自動検査

Godot 4.7.2で**15種類17条件が全PASS・終了0**。最終一覧 `.godot/enemy_defeat_all_results.json`。Script／Shader構文・画像／Resource参照・解放時の漏れエラーなし。

| 検査 | 最終結果 |
|---|---|
| enemy_defeat_audio 実描画60／30fps上限 | 713／415項目PASS（観測回数は変動） |
| 同・別プロセス--reload | PASS |
| enemy_tactics | 1242項目PASS |
| target_marker_shadow | 10項目PASS |
| enemy_sword_combat | 441項目PASS（観測回数は変動） |
| enemy_followup | 221項目PASS |
| enemy_attack_warning | 110項目PASS |
| enemy_sprites | 408項目PASS |
| m09_enemy_dash | 171項目PASS |
| m09_timing | 旧予告／回復と魔導士の弾速度・間隔PASS |
| m09_startup | 実main・左攻撃／右防御・モード切替PASS |
| combat_feedback | 632項目PASS（観測回数は変動） |
| m08_defense | 防御／方向帰還／安全移動PASS |
| m07_chain | 複数敵3連撃／照準／カメラ／帰還PASS |
| defeat_return_timing | 1869項目PASS |
| action_audio | 122項目PASS |

共通SEの実ストリーム／音量／ピッチ・共通設定編集時の両者反映、空振り／Guard／Fire1／魔導士除外、極端に短い0.02秒の空振りでも1回の風切り音を検証。攻撃時刻は既存時計を読むのみ。

両敵×4カメラ方向、飛行中の回転、1152×720／800×600のViewportで画像全体の外側到達を検証。最終30fpsの観測では約0.53〜0.67秒で全8例が通常のoffscreen終了（`.godot/enemy_defeat_measurements.json`）。途中の描画キャプチャ `.godot/enemy_defeat_midflight.png`を目視確認した。

実production敵への致死打では、表示ON／OFFの死亡後終了時刻が同じ（物理tick許容0.05秒以内）、対象なしで残り時間を維持、実体削除中も主人公の攻撃シーケンスを継続する。別の生存敵がいる場合は実3連撃・ストック0／実HP減少・元位置への帰還を確認し、ストック回復後のL相当再選択も合格。元の敵を先にfreeしても表示が継続し、Camera欠落はtimeout、NONE／Resource保存も確認。

新しい敵SEの初期検査では、描画fixtureのプレイヤーにcombatがないケースと、修正時の型推論エラーを検出した。接続先の存在確認・明示Node型で修正し、影響した新検査／描画／起動／被弾／防御／連撃を再実行して最終ログにScriptエラーがないことを確認。PASS行だけで判定しない。

最終editor importは終了0（`.godot/defeat_import_final.log`）、最後に変更した音声Scriptの--check-onlyも終了0。既存の証明書ストア読込／エディター設定保存失敗に加え、GLES3の`_save_to_cache`でキャッシュファイルを開けないログが一部にある。Shaderのコンパイル／実描画は成功しており、キャッシュ保存失敗の原因自体は未特定。ゲーム側の構文／参照／実行エラーと分けて記録する。

git diff --checkと全編集Scene／Resource参照先実在、元画像／音・主人公／InputMap・武器／Motion・既存Shader・照準／追跡／命中計算の非変更を確認。旧描画fixtureは独立表示をリセット時に片づけ、撃破後の位置検査は正常な解放済みも許容した。戦闘の時間／HP条件は緩和しない。

再現（プロジェクトルートで1本ずつ）：

```powershell
$godotExe = 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --editor --quit
& $godotExe --path . --script res://tests/enemy_defeat_audio.gd
& $godotExe --path . --script res://tests/enemy_defeat_audio.gd -- --fps30
& $godotExe --path . --script res://tests/enemy_defeat_audio.gd -- --reload
```

他の回帰は表のtests/<名前>.gdを同じ--scriptで実行。ログ・画像・測定JSONはGit除外の.godot内。自動描画／合成入力とユーザーF5・聴感の受入を区別する。

## F5確認と未確認事項

1. F8→F5、近接敵。Fire1が予告入り際1回、剣振りにEvasion1、実命中でSlash1となることを確認。右／Iの実Guard成功はSword2、姿勢だけでSword2が鳴らず、命中音と重ならないことを確認。
2. 主人公と雑兵の音量・ピッチを聴き比べる。共通Feedbackを1項目ずつ編集して保存→再起動し、両者へ反映されることを確認。
3. 近接／遠距離それぞれを倒し、HP0直後に攻撃・接触・金色ターゲットが無効になること、少し浮いて勢いよく画面外へ出てから消えることを確認。
4. Q/E各方向・飛行中の回転、壁や段差の近くで、途中停止や画面内での突然の消失がないことを確認。飛行中は既定で約0.5〜0.8秒を目安とし、好みでDefeat設定を調整する。
5. 1撃目／2撃目で倒した後も残り時間を維持して帰還すること、別の生存敵がいれば連撃を続け、L／クリックの切替と3連撃・帰還が正常なことを確認。
6. WASD／Space・防御・方向帰還、直前照準／雑兵の帰還後歩行、魔導士の弾、既存SE・白flash／火花と金色マークの影OFFを確認。
7. リセット／敵切替で前の飛行表示や当たり判定が残らないことを確認。

ユーザーF5での聴感・演出速度／方向の自然さは未確認。多数同時撃破・任意の複雑地形／実機パッド／長時間性能は既存残件として継続。証明書・エディター設定／GPU Shaderキャッシュ保存エラーは、ゲームの参照・構文／描画検査とは分けて記録する。
