# 魔導士：大きな炎被弾・Fire3・詠唱確定と10秒待機

2026-10-30、ADR-045。M09基本戦闘完了を維持。今回のF5見た目／聴感／操作確認はユーザー未実行、M10は別指示待ち。commit／push未実行。

## 目的・開始時・受入条件

ユーザーの3指定：命中エフェクトを主人公が隠れる大きさにする、炎弾の発射時にFire3、魔法陣を出した後は主人公が攻撃範囲外へ離れても発射し攻撃後に約10秒待つ。

再開時はADR-044までの実装／進捗と一致し、差分はエディター生成の未追跡 `~libeffekseer.x86_64.dll` のみ。元の依頼の途中では実装前の確認までだったため、今回まとめて実装・検証した。Issueは未作成。

対象は魔導士Resource・既存のProjectile詠唱／発射分岐と表示音設定。受入は実レンダラーで通常／Guardの主人公を炎が覆うこと、実生成時にだけFire3が1回鳴ること、詠唱後7m／11mで実際に発射、開始範囲6m・遮蔽／死亡・同時1発と弾の速度／距離・物理戦闘は維持すること、次の詠唱が攻撃終了から約10秒後になること。未決定の最終バランスを確定しない。

## 命中エフェクトと音

`mage_magic_visual.tres` のHit Effect Scaleを明示0.3へ設定。前回の0.06から縦横／奥行きの倍率を5倍とし、FireOne1の原本・既存のFire2／ダメージ3コマ／Guard中の共通表示を維持する。汎用Resourceの既定0.06は変更せず、この魔導士だけに適用。見た目の拡大で衝突半径0.2m・HPダメージ10は変わらない。

提供 `RPGツクールMZのaudio/se/Fire3.ogg` を `assets/audio/sfx/mz_fire3.ogg` へ無加工コピーし、Magic VisualのLaunch Soundへ割当。Volume=-12dB／Pitch=1.0は今回の初期値。詠唱のMagic1／pitch0.9、命中のFire2は別契機のまま。

Projectile生成・設定／方向確定・shotsへの追加が成立してからだけ発射音を再生し、projectile_releasedを通知する。警告開始・射程／壁等での不発・同時弾上限で生成しない場合はFire3を鳴らさない。独立したAudioStreamPlayerを敵の親へ追加し、弾消失／発射直後の敵撃破で音を切らず、finishedで自然解放する。配布プラグイン・音声原本は未変更。出典と未確認の素材利用条件は素材台帳へ記録。

## 詠唱開始後の射程外発射

EnemyAttackDataに `commit_projectile_on_windup`（既定false）を追加し、魔導士のranged_attackだけtrue。開始前は従来どおり6m以内・視線・cooldown等を確認し、範囲外から新しく詠唱する機能は追加しない。

WINDUP／ATTACK中の該当Projectileは、攻撃開始範囲6mやleash距離10mを主人公が超えただけでは中断しない。発射時の射程再検査もこの明示フラグのときだけ省き、従来どおり発射時点の実3D主人公位置へ向ける。発射後の追尾はしない。最大飛距離13.2m／速度5m/s／寿命6秒は維持し、主人公がそれ以上遠ければ届かず終わることがある。

壁で視線が遮られた場合、主人公／魔導士のHP0、同時弾数上限は従来条件を維持。leash超過時は一度の確定詠唱を終えた後に帰還するフラグを保持し、回復中に敵を範囲外へ歩かせ続けない。雑兵と明示フラグfalseの攻撃は以前の処理を維持する。床面魔法陣／開始音は既存通知をそのまま使用し、再開始しない。

## 10秒の区間

魔導士のRecovery Seconds=10.0、Minimum Attack Interval=10.0を保存。実攻撃状態0.12秒が終わってRECOVERYへ入ってから10秒間は新しい詠唱を始めない。次の1秒の詠唱後に次の炎弾を生成するため、発射から次の発射までは約11.1秒になる。

回復中の射程内停止／射程外への安全な接近は従来どおり。プレイヤーが範囲内へ戻っただけで回復時間を短縮しない。leash超過など帰還が必要な場合は待機後に帰還し、新しい攻撃の成立条件も改めて検査する。設定は試作・ユーザー調整可能な値。

## 設定と変更ファイル

| Resource | 項目 | 今回値 |
|---|---|---|
| mage_magic_visual.tres | Hit Effect Scale | 0.3（旧0.06の5倍） |
| 同上 | Launch Sound／Volume／Pitch | Fire3／-12dB／1.0 |
| ranged_attack.tres | Commit Projectile On Windup | true |
| 同上 | Recovery Seconds／Minimum Attack Interval | 10.0／10.0秒 |

ソース：enemy_attack_data.gd、practice_enemy.gd、magic_visual_settings.gd。Resource：上表2ファイル。素材：Fire3コピー／import設定。生成手順：prepare_mage_fire_effects.ps1へFire3のコピーを追加。検査：新規mage_cast_commitment.gdと生成UID、m09_timingの期待値を新しい発射間隔へ更新。ドキュメント：ADR-045・進捗／AGENTS／README／システム仕様／検査計画／素材台帳・前回監査への履歴注記と本書。

## 検証・再現

Godot 4.7.2.stable.official.ed1daf0bf、Compatibility／GTX 1080、物理60Hz、描画fps上限60／30。開いたエディターとのDLLコピー競合を避け、同一ソースの `.godot/mage_fire_validation/` で検査。`tools/validate_mage_fire.ps1 -ImportOnly` で再複製・importできる。検査プロセスだけAPPDATA／LOCALAPPDATAをworkspace内へ分離し、ユーザーの個人設定／エディターと一時DLLを変更しない。

新検査は60／30とも29項目PASS・終了0。開始時6mの維持、警告後7m／11mで現在位置へ向けて発射、Fire3が生成時だけ1回・敵撃破後も完走、壁／主人公死亡／同時弾数上限による不発時にFire3が鳴らないことを実際の物理処理で確認。保存／別プロセス再読込も検査する。

10秒待機を実際のphysics frame数で計測し、両fps上限で攻撃終了→次の詠唱10.0167秒、発射→次の発射11.15秒。通常／GuardでFireOne1を実描画し、元画像の色が基準画像に実在する不透明な主人公画素を使ってA/B比較。表示ピークでそれぞれ約99.17%／99.68%が炎で変化し、主人公を覆うことを目視した。全再生時間の全フレームを同じ不透明度で隠す指定ではなく、既存素材の出現・消失を維持する。

再現例（Godotは1プロセスずつ。競合がある場合は `--path` を検証用コピーへ）：

```powershell
$godotExe = 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --editor --import
& $godotExe --path . --script res://tests/mage_cast_commitment.gd
& $godotExe --path . --script res://tests/mage_cast_commitment.gd -- --fps30
& $godotExe --path . --script res://tests/mage_cast_commitment.gd -- --reload
& $godotExe --path . --script res://tests/m09_timing.gd
```

計測／画像は検証用コピー内 `.godot/mage_cast_metrics.json`／`mage_large_impact_guard_false.png`／`mage_large_impact_guard_true.png`。実行ログは元プロジェクト `.godot/mage_cast60.log`／`cast_final_*`（Git対象外）。最終の関連回帰結果は本書末尾へ追記する。

## 最終結果
最終の検証用コピーは11条件すべてPASS・終了0：新規60／30（各29項目）、別プロセスreload、mage_fire_feedback（33項目）、mage_magic（124項目）、m09_timing、m09_enemy_combat（56項目）、enemy_sword_combat（445項目）、enemy_jump_strike（547項目）、m09_startup、m08_defense。importと最終回帰ログにScript／Parse／Shader／Resourceエラー・警告なし。`git diff --check` 合格。

検証コピーと元プロジェクトの変更コード・Resource・Fire3をhashで照合しバイト一致。Fire3のGodot生成import設定と対応するキャッシュも元プロジェクトへ保持した。既存の一時DLLには触れていない。

元のプロジェクトでも新検査60fpsを実行し、29項目PASS・終了0、計測10.0167秒／11.15秒・被覆率約99%を再確認。`.godot/cast_final_root60.log` にエラー・警告なし。元プロジェクトの `.godot/mage_large_impact_guard_false.png`／`mage_large_impact_guard_true.png` と `.godot/mage_cast_metrics.json` にも結果を保存した。

## F5での確認（ユーザー未実行）


1. F8で停止し、インポートを待ってF5→「遠距離敵」。詠唱開始後、主人公を6m外へ離し、そのまま発射すること。詠唱音Magic1の後、実発射にFire3が1回鳴ること。
2. 通常／右クリック・I防御中に炎弾を受け、主人公を覆う炎単体1とFire2、ダメージ3コマが出ること。防御保持中は既存どおり防御表示へ戻ること。
3. 攻撃終了から次の魔法陣まで約10秒、発射どうしは約11.1秒となること。射程外でも詠唱前は歩いて接近し、待機を飛ばして連射しないこと。
4. 壁／死亡／モード切替時の停止、床面魔法陣が本体を塗らないこと、雑兵の予告／剣／ジャンプ中命中と物理Guard、主人公の移動／攻撃／連撃／帰還を確認する。

F5の見た目・聴感／操作、任意の複雑地形・実機パッド・他OS／エクスポート・長時間負荷は未確認。M09基本戦闘完了と今回追加調整のF5待ちを区別する。
