# M09完了後：弾む撃破飛行・Cry1

2026-10-29／ADR-039。M09基本戦闘完了を維持。今回の弾み／聴感はユーザーF5確認待ち。commit／push未実行。

## 開始時と変更範囲

開始HEAD `9ba490e`、作業ツリークリーン。AGENTS・開発状況・指定仕様08／10／11／12／14・ADR-038監査と現在の撃破表示を確認。旧単一のsin弧を調整するだけで、HP0即DEAD／衝突・選択無効、表示／実体の独立・画面外判定／安全期限、コンボ／帰還・敵AI・既存画像／SE再生処理は変更しない。

## 弾みの実装

前方向の速度×経過時間は従来どおり。そこへ画面上方向の高さだけを加える。初回は全体時間の45%で勢いよく跳ね上がって戻り、残り55%に小さな弧を等分配する。各弧はsinの正の半周期で、つなぎ目の高さは0、途中で画像位置を瞬間移動させず前方の基準移動も止めない。

- 最初の跳ね上がり：0.9m相当（既存Lift Heightを再利用、旧初期0.7から変更）。
- 追加の小さな弾み：2回。
- 最初の小さな弧：初回×0.45＝0.405m相当。
- さらに小さな弧：前の小さな弧×0.55＝0.22275m相当。
- 目安0.65秒で、初回の頂点は約0.146秒、小さな弧の頂点は約0.382秒／0.561秒。

上下は弾みとして反転するが、前方の基準移動・最後の攻撃方向は変えない。Camera／Viewportへの投影、画像全体が画面外＋24pxへ出てから解放する方式と安全期限はそのまま。小さな弾み0回では単一の初回弧になる。画面端が近い場合など、全ての小さな弧を終える前に正常に画面外へ出ることはある。

## Cry1と寿命

実ファイル：`RPGツクールMZのaudio/se/Cry1.ogg`（6311bytes）。無加工コピーは `assets/audio/sfx/mz_cry1.ogg`。両者SHA256 `d5cb7e1cd3600774426771ddd46a3c6a08607b61c362ae7e6452b14267cd99bc` が一致。元ファイルは変更しない。Godot importはloop=false。出典はユーザー提供MZ標準SEとして素材台帳へ記録し、ライセンスはnot_verifiedのまま。

HP0から呼ばれるDefeatPresentation.startの既存startedガード内で、表示開始と同じイベントから1回だけ再生する。非致死ダメージ、同じ敵への二重_die／startでは再生しない。NONEで表示を無効にしてもSoundが指定されていれば再生し、Sound=nullで撃破音を無効化できる。

AudioStreamPlayerは実体／表示の子ではなく、それらと同じMainの子。表示の画面外削除・実体解放・表示の強制削除で止めない。終了判定に演出時間のTimerを使わず、音声自身の自然なfinished通知で解放する。シーン全体の終了時は通常どおり片づく。pitch_scale=0.5は再生時に設定し、音高／再生速度が半分・再生時間がおおむね2倍になる。元の音声データは加工しない。

## Inspector設定

`resources/enemies/melee_practice.tres`／`ranged_practice.tres` の **Defeat** が参照する `resources/enemies/flyoff_defeat.tres` を開く。両敵で共用しているため、敵別に調整する場合はResourceを複製して別割当する。

| 項目 | 初期値 | 範囲／意味 |
|---|---|---|
| Minimum Fly Speed（既存） | 18.0m/s相当 | 1〜60。端までに必要なら速める |
| Lift Height（既存を再利用） | 0.9m相当 | 0〜3、初回の高さ |
| Bounce Count | 2 | 0〜4、初回以外の小さな弾み回数 |
| Secondary Bounce Scale | 0.45 | 0〜1、初回に対する最初の小さな弧の高さ比 |
| Bounce Decay | 0.55 | 0〜0.95、それ以降の高さの減衰比 |
| Flyoff Duration（既存） | 0.65秒 | 0.2〜1.5、目安時間 |
| Maximum Lifetime（既存） | 2.5秒 | 0.8〜5、実行時は目安時間＋0.1秒以上 |
| Defeat Sound | mz_cry1.ogg | AudioStream、nullで無音 |
| Defeat Volume Db | -12.0dB | -60〜0、0.1刻み |
| Defeat Pitch Scale | 0.5 | 0.5〜2、0.01刻み |

速度・時間・初回高さは既存項目を活用し、重複した設定値を作らない。Resource保存／再起動後の値を別プロセスで検査した。

## 変更ファイル

- scripts/effects/enemy_defeat_settings.gd（弾み／Cry1設定）、enemy_flyoff.gd（上下の弧）、enemy_defeat_presentation.gd（独立した単発SE）
- resources/enemies/flyoff_defeat.tres（Cry1割当）
- assets/audio/sfx/mz_cry1.ogg、同.import（新規の無加工コピーとGodot生成情報）
- assets/ASSET_REGISTER.csv（素材出典・SHA・用途）
- tests/enemy_bounce_cry.gd、同.uid（新規）
- AGENTS.md、docs/08・10・11・12・14、DEVELOPMENT_STATUS、前回監査の訂正注記、本書

主人公・敵AI／HP計算・剣／命中／防御／予告のSE設定／再生処理・画像・InputMap・Motionは変更していない。

## 自動検査結果

Godot4.7.2で **11種類13条件が全PASS・終了0**。最終一覧 `.godot/enemy_bounce_results.json`。最終ログにScript／Shader／Resource参照・実行エラーなし。

| 検査 | 結果 |
|---|---|
| enemy_bounce_cry 実描画60／30fps上限 | 2909／2705項目PASS（観測回数は変動） |
| 同・別プロセス--reload | PASS |
| enemy_defeat_audio | 711項目PASS（観測回数は変動） |
| enemy_sword_combat | 445項目PASS（観測回数は変動） |
| enemy_attack_warning | 110項目PASS |
| enemy_sprites | 408項目PASS |
| m09_startup | 実mainの左攻撃／右防御・モード切替PASS |
| combat_feedback | 630項目PASS（観測回数は変動） |
| m08_defense | 防御・方向帰還／安全移動PASS |
| m07_chain | 複数敵3連撃／照準／カメラ／帰還PASS |
| defeat_return_timing | 1869項目PASS |
| action_audio | 122項目PASS |

新検査は初回＋小さな弧0／1／2／4回、各ピークの減衰・高さ範囲・両端0を検証。実Spriteの上下位置も設定曲線に一致し、前方の基準移動が単調であることを確認。両敵×4カメラ方向でHP0即無効化、Cry1単発／pitch0.5、通常の画面外終了・音声の自然なfinishedと自己解放、表示の強制削除／実体解放後の音声継続を確認した。

既存検査で飛行中カメラ回転・異なるViewport・完全画面外解放／Camera欠落の安全期限、実体削除後のコンボ時間維持・生存敵への3連撃・L再選択・帰還、既存SEを確認。単なるPASS表示だけでなく全ログのエラーも検査した。

最終editor importは終了0、画像／Script／Resource読込エラーなし。エディター設定をworkspace外へ保存できない既存診断は別記する。今回の実行ログには以前の証明書／Shaderキャッシュ保存エラーは現れなかったが、その環境問題を修正済みと断定しない。git diff --check・Cry1完全一致・台帳の列数／ID重複なしも確認。

再現（プロジェクトルートで1本ずつ）：

```powershell
$godotExe = 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --editor --quit
& $godotExe --path . --script res://tests/enemy_bounce_cry.gd
& $godotExe --path . --script res://tests/enemy_bounce_cry.gd -- --fps30
& $godotExe --path . --script res://tests/enemy_bounce_cry.gd -- --reload
```

他の検査は表のtests/<名前>.gdを同じ--scriptへ指定。ログはGit除外の `.godot/bounce_*.log`、初期弾みのサンプルは `.godot/enemy_bounce_curve.json`。自動描画とユーザーの見た目／聴感の受入を区別する。

## F5・未確認事項

1. F8→F5、近接敵を倒す。最初に大きく跳ね上がり、その後小さく弾みながら前へ飛び続け、画像全体が画面外へ出てから消えることを確認。
2. 遠距離敵へ切替え、魔導士も同様に動くことを確認。Q/Eの各方向・壁付近と、飛行中に敵の判定／攻撃・金色マークが残らないことも確認。
3. HP0と同時に低いCry1が1回鳴り、表示が消えた後も最後まで鳴ることを確認。連続撃破では別の敵の声が重なることはあるが、同じ敵で二重再生しないことを確認。
4. Defeat ResourceのLift Height／Bounce Count／Secondary Bounce Scale／Bounce Decay／時間・速度、音量／ピッチを1つずつ調整し、保存・再起動でも維持することを確認。
5. 左／J攻撃・右／I防御、Fire1／Evasion1／Slash1／Sword2、WASD／Space、3連撃／ターゲット切替／撃破後の時間維持／帰還と既存の白flash／火花を確認。

実機F5の軽快さ・Cry1の聴感／最終音量はユーザー確認待ち。多数同時撃破・長時間性能・任意の複雑地形／実機パッドなど既存の未検証は継続。M09基本戦闘完了は維持する。
