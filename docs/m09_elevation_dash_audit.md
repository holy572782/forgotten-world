# M09追加改善：片手剣の上下攻撃と跳躍踏み込み（2026-10-30、ADR-048）

## 対象と変更

開始HEAD bb0327a。開始差分は未追跡のEffekseer一時DLLのみで保持した。M09基本戦闘完了、今回の追加改善のユーザーF5待ち、M10別指示待ちを区別する。

主人公と雑兵の片手剣だけを対象に、攻撃高さ→跳躍踏み込み→帰還とコンボの順で実装・検査した。魔導士の魔法／確定詠唱、両敵の通常歩行／自動ジャンプ、主人公の通常ジャンプ／歩行、画像・音声・シーン・地形は変更しない。

### その場攻撃

WeaponDataのHit Height Up／Downを片手剣だけ各1.8mに設定。足元の実高低差と既存Sweepの水平リーチ／扇形を使う。旧武器は負値で従来のHit Height Toleranceへフォールバックする。雑兵は同じ武器設定を参照し、敵専用overrideが必要な別種には従来の対称高さoverrideも維持する。

共通MeleeTerrainは剣の地形遮断だけを扱い、移動やダメージを作らない。同じ高さでは従来の全身幅・連続床のstrike_clearを維持。異なる足場では段差の縁を越えて届く高さの剣経路と上下の接続線、足元の連続支持を確認する。床下／天井・壁／遮蔽物・穴を無条件に通さない。AttackHitboxとダメージ処理は既存の1振り1命中／HP重複除去を使う。

### 跳躍踏み込み

ElevationPathで共通の可否を計画し、主人公の候補・金色マーク・クリック／J・連撃先と雑兵の予告／再照準へ使用する。水平攻撃半径内→その場で剣が届くか→着地点→往路／復路の全身経路の順。近距離なら移動を省略し、ほぼ同じ高さなら元のDashPathを使う。

高低差がある場合は、対象の手前の安全な停止点を探す。両カプセルの実衝突、着地足元の支持、途中の床、壁／天井・home範囲（雑兵）を確認する。身体の小さい敵も飛び越えないようキャラクター層の経路を別に検査する。往路だけでなく元の位置への復路も成立しなければ開始しない。

JumpArcの既存放物線計算／全身掃引を拡張し、上りは水平移動を後半へ寄せ、下りは早めに足場から離れる。上下位置は放物線、水平方向は固定し、検査と実移動で同じ関数を使う。通常ジャンプの既定引数は従来どおりで、敵の通常自動ジャンプの軌道を変えない。

最高点は通常ジャンプの到達高さと武器側上限の小さい方で制限する。飛行時間は既存Motionの速度／最小最大時間を参照しつつ、安全な跳躍に必要な時間より短くしない。単純な直線補間や地形無視は行わない。初期1m試験では上り約0.416秒、下り約0.477秒（接触状態で微差）。平地の時間／smoothstepは従来どおり。

### 帰還・防御・連撃

CombatFlightは検査済みの飛行をnative move_and_collideで実行し、攻撃や防御の判断は既存の所有者へ残す。着地と支持面を確認してから攻撃し、着地後のApproach Attack Delayも維持する。飛行中に新しい障害物が現れた場合は落下／安全着地へ移し、床が消失した場合の落下にも安全期限を設ける。

空中でGuardへ切り替えても飛行の時計は止めない。既存の軽減／音／姿勢を使用し、安全な着地後にGuard維持または帰還する。方向入力の帰還は空中で反転せず、現在の安全な着地まで進んでから帰る。対象撃破／移動／画面外も空中で停止させず着地後に既存の空き攻撃時間または帰還へ進む。

高低差を含む連撃は各踏み込み開始点を保存し、帰還時は逆順の安全な区間を通ってシーケンス初期のreturn_anchorへ戻る。平地だけの戦闘は従来の直接帰還。後から帰路が塞がれた場合は足場上で終了し、位置を代入するワープはしない。カメラ位置固定／解除・予約1個・最大回数／支払い／敵撃破後の時間維持は元の仕組みを使う。

雑兵の予告中は実主人公位置を追跡し、固定時刻を維持。移動の計画には実地面、命中には実際の足元高さを使うため、主人公の通常ジャンプだけで中断しない。赤い攻撃態勢／Fire1・剣／命中音・帰還後の周辺移動・撃破表示は維持する。

## Inspector

主人公：Player → TargetDash → Equipped Weapon。雑兵：Settings → Attack → Weapon。同じ片手剣Resourceを参照する。別の武器／敵には複製したResourceを割り当てる。実行中の攻撃は設定をsnapshotし、次の攻撃から調整を適用する。

| 項目 | 初期値 | 単位／範囲 |
|---|---:|---|
| Hit Height Up / Down | 各1.8 | m、各-1～5。-1は旧対称設定を利用 |
| Elevation Travel → Enabled | ON | 武器ごとの跳躍踏み込み |
| Maximum Ascent | 1.0 | m、0～1.1 |
| Maximum Descent | 1.1 | m、0～1.1 |
| Apex Height | 1.1 | m、0.1～1.1。跳躍最高点の上限 |
| Minimum Hop Height | 0.18 | m、0.05～0.5。下降時などの小さな跳ね上がり |
| Gravity | 20 | m/s²、1～40。跳躍のテンポ |
| Motion → Approach Speed / Return Speed | 既存保存値 | 既存の武器別Motion設定を継続利用 |

初期値は暫定。攻撃の高さと登り／下りの移動高さは独立。下降可能でも安全な上り復路が作れない場合は拒否する。上限ぎりぎりの足場や狭い足場は、全身と床接触の余裕により拒否する場合がある。

## 変更ファイル

- 新規：scripts/combat/melee_terrain.gd、elevation_travel_settings.gd、elevation_path.gd、combat_flight.gd、resources/weapons/sword_elevation_travel.tres
- 実装更新：scripts/combat/weapon_data.gd、melee_sweep.gd、jump_arc.gd、scripts/player/target_dash.gd、scripts/enemies/practice_enemy.gd、enemy_attack_data.gd、enemy_melee_geometry.gd、resources/weapons/one_handed_sword.tres、resources/enemies/melee_attack.tres
- 検査：tests/elevation_strike.gd、elevation_dash.gd、elevation_controls.gd、elevation_settings.gd（新規）、tests/enemy_jump_strike.gd、tests/fixtures/combat_scene.gd、Godotの新規UID
- 記録：AGENTS.md、docs/DEVELOPMENT_STATUS.md、08_DECISIONS.md、10_SYSTEM_SPEC_GODOT.md、11_CODEX_IMPLEMENTATION_PLAN.md、12_TEST_PLAN.md、14_TARGET_DASH_COMBAT_SPEC.md、本書

旧flat fixtureは従来の対称高さと跳躍なしへ明示固定し、旧操作／テンポの回帰を行う。新規検査では本番片手剣を明示的に使用する。enemy_jump_strikeの旧1.4m／主人公0.3mの期待だけ今回の1.8mへ更新し、短い敵専用override・地面と実高さの分離・壁／崖／実Spaceと回避／魔法は維持する。

## 検証

第1段階：elevation_strike 343項目・enemy_sword_combat 445項目・m07_chainがPASS。第2段階：両者×上下のelevation_dash、上下攻撃343項目、旧剣445項目・m09_enemy_combat 56項目がPASS。

最終確認はGodot 4.7.2.stable.official.ed1daf0bf／Compatibility／GTX 1080、物理60Hz・実描画上限60／30fps。**14種類17条件すべてPASS・終了0、実行ログにエラー／警告なし**。観測assertion数はphysicsと描画の対応で変動する。

| 検査 | 結果 |
|---|---|
| elevation_strike | 345項目PASS（実坂の主人公も含む） |
| elevation_controls／60fps上限 | 263項目PASS |
| elevation_controls／30fps上限 | 150項目PASS |
| elevation_dash／60fps上限 | 302項目／214飛行サンプルPASS |
| elevation_dash／30fps上限 | 164項目／106飛行サンプルPASS |
| elevation_settings／save・別プロセスreload | 各PASS |
| enemy_terrain | 4356項目PASS |
| enemy_auto_jump | 5837項目PASS |
| enemy_sword_combat | 445項目PASS |
| enemy_jump_strike | 543項目PASS |
| enemy_tactics | 1242項目PASS |
| mage_cast_commitment | 29項目PASS |
| in_place_attack | 3273項目PASS |
| m08_defense | 防御／方向帰還・入力／状態／安全性PASS |
| m07_chain | 3体連撃・照準／帰還／無効対象切替PASS |
| m09_startup | 実mainの敵攻撃・左攻撃／右Guard・UI切替／リセットPASS |

その場上下1.8mの境界・1回HP減少、両者の上り／下りで着地後だけ攻撃すること、空中Guardの軽減／即時解除と飛行継続、方向帰還は現在の安全な着地後、異なる高さの3回攻撃で初期anchorへ戻ることを確認。天井・穴・小さい敵の飛び越え・着地点の占有／個別の上り下り制限を拒否。帰路へ新しい壁を置いた場合も上の支持面で安全終了することを確認した。

回帰で坂の剣用地面検出が平坦条件に依存する不具合を検出し、歩ける斜面用の検出と半径に応じた支持面の探索深さへ修正。主人公の坂上の足場確認も実カプセルとnative床を使用し、候補表示と実命中を確認した。跳躍着地点の平坦・全身支持条件は維持する。旧enemy_terrainの「戦闘後の通常追跡」ケースだけ戦闘跳躍を明示OFFにし、今回新設した戦闘跳躍で通常追跡検査を省略しないようにした。普通の自動ジャンプはそのまま使用する。

敵の通常坂／階段と自動ジャンプ・home、照準固定／回避猶予／ジャンプ中の命中、主人公の既存Guard／方向帰還／3連撃／近距離省略、実mainの入力／UIを回帰した。魔導士は回復約10.0167秒・発射間隔11.15秒で従来値を維持。実描画の跳躍／着地後の剣と命中フラッシュも目視したが、F5の実操作／自然さはユーザー確認待ちとして残す。

検証は開いたエディターとDLLを分離した同一ソース `.godot/mage_fire_validation/` で実施。変更実装／Resource／検査とUIDの29ファイルがrootとバイト一致。最終headless editor import終了0・エラー／警告なし、git diff --check合格。結果一覧 `.godot/elevation_results.json`、実行ログ `.godot/elevation_final_*.log`、最終import `.godot/elevation_import_final.log`。画像は検証コピー内 `.godot/elevation_arc.png`／`elevation_landed_attack.png`（Git対象外）。

再現は `tools/validate_mage_fire.ps1 -ImportOnly` でコピーを準備し、Godotに `--path .godot/mage_fire_validation --script res://tests/elevation_strike.gd`（またはelevation_dash／elevation_controls／elevation_settings）を渡す。追加引数 `-- --fps30` または設定検査の `-- --reload` を別プロセスで実行する。APPDATA／LOCALAPPDATAはworkspace内 `.godot/mage_runtime_appdata` を使用する。commit／pushは未実行。

## F5確認（ユーザー実操作は未実行）

1. F8→F5。平地で左クリック／J・3連撃と通常の踏み込み／帰還を確認。
2. 片手剣の水平リーチ内で、主人公と雑兵が階段上／下へ移動せず命中すること。近くても壁・床下の敵には当たらないこと。
3. リーチ外・攻撃候補半径内で1m段差の相手を指定し、跳躍→着地→攻撃→元の高さへの帰還を確認。下の足場への攻撃も確認。
4. 高すぎる段差・崖／穴・低天井・着地点が他キャラで塞がれた条件では候補／攻撃を拒否すること。
5. 踏み込み／帰還中に右クリックまたはIで防御。空中停止せず着地し、防御解除後に帰還すること。方向キーの帰還も着地後に行うこと。
6. 高→低→高の対象切替連撃、途中撃破、L選択、Q/Eの4方位、カメラ位置固定と終了後の追従再開を確認。
7. 雑兵の赤い攻撃予告・位置確定と回避猶予・剣／音・帰還後の移動、両敵の普通の坂／階段歩行と自動ジャンプ、魔導士の魔法陣／炎弾／Guard貫通を確認。

任意の複雑地形・動的な全面床消失からの回復・多数の敵／長時間性能・実機パッドは未検証。任意迷路を迂回するNavMesh探索は今回追加しない。
