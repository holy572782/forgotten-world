# M09 鉄の剣の分離アニメーション（2026-10-21、ADR-018）

状態：実装・自動／描画検査とユーザーの手動確認を分ける。M09は検証待ち、M08完了（試作範囲）と既存残件は維持する。

## 今回の範囲

ユーザー提供`画像フォルダ/武器/鉄の剣.png`を`assets/sprites/weapons/iron_sword_attack.png`へ無加工コピー。SHA256は両方`1b666a412cf6c3ddfa00df05f6ff83d69449e1bda5b41a2668ac2ad3748953ba`。336×448px、112×112pxの3列×4行。下・左・右・上を既存主人公と同じ方向名へ割り当てる。切り出しはRect2(列×112,行×112,112,112)、filter_clip=true。無損失・nearest・mipmapなし・透明RGB補正なし・自動3D圧縮なしで全画素を維持する。

| 指示 | 実装・確認 |
|---|---|
| 48px主人公を維持／112px剣の独立表示 | WeaponSwingをAnimatedSprite3Dへ更新。主人公PNG・SpriteFrames・PlayerSpriteは変更なし |
| 中心一致・同ピクセル倍率 | 主人公のtransform・offset(0,23)・pixel_size=0.0375・billboardを継承。初期方向offsetは全て0。キャンバス48と112を維持し、112→48へ縮小しない |
| 各3コマ・4方向・同期 | 主人公のanimation・frame・frame_progressを攻撃開始／変更通知と各描画tickで参照。剣自身の時計は進めず、ずれの累積を防ぐ |
| 方向別位置調整・武器差し替え | WeaponData.attack_visual→WeaponAttackVisualData。attack_framesとoffset_down/left/right/up、単位px（+X右・+Y上） |
| 戦闘・踏み込み・連撃・帰還を維持 | TargetDash・Controller・Path・武器範囲／威力／時間／ストック値は変更なし。剣から命中・終了信号を送らない |
| 盾／防御を維持 | PlayerSprite・DamageVisual・盾データ／画像／防御処理を変更せず、元の表示優先を維持 |

## 手動で確認する箇所

中央一致と同倍率は検査済み。ただし提供配置のままだと**上向きの一部コマで柄と手元に隙間が見える**。作者調整済みという指定と原寸・中央合わせを優先し、自動の各コマ補正や描き直しを行っていない。方向別offsetでその向き全体を寄せられるが、コマごとの柄位置差は元シート側の調整になる。これを手元の受入済みとはしない。敵の身体による剣の通常深度遮蔽もある。

1. F8で停止→F5で再起動し、J／クリックで敵へ攻撃。3コマ、手元、命中、帰還を確認する。
2. Q/Eで4方向へ回転し、攻撃中にも回して中心・方向・フレームが一致するか確認する。
3. 連続入力による連撃、方向入力の帰還、Iの割り込みと鉄の盾を確認する。剣が残らないことも確認する。
4. 範囲確認は`scenes/tests/weapon_sweep_trial.tscn`をF6、中央を左クリック。従来の3体HP40→30・ストック3→2・帰還を確認する。
5. 必要な表示調整は`resources/weapons/iron_sword_visual.tres`の4方向offset。画像差し替えはそのattack_framesを変更するか、別WeaponAttackVisualDataをWeaponData.attack_visualへ設定する。各方向名はattack_down/left/right/up・各3コマ。

## 検査と再現

新`tests/iron_sword_animation.gd`は元PNGとコピー／インポート画素・12矩形、48/112キャンバスの中心・倍率、4方向3コマ、フレーム内進行、Q/E実入力中の行変更、Resource差し替え・方向offsetの分離、画像欠落・null Atlas・再生途中欠落、通常被弾・Guard、実命中1回・ストック・帰還を検査する。

既存`tests/weapon_sweep.gd`は112px表示に関する期待だけを更新した。旧16pxの回転軌道ではなく、同じ中心・向き・フレームを確認する。距離／角度行列・複数命中・壁・高低差・予約・ストック・死亡・単体モードなどの戦闘条件は変更していない。

```powershell
$godotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path . --script res://tests/iron_sword_animation.gd --log-file .godot/iron_sword_headless.log
& $godotExe --path . --script res://tests/iron_sword_animation.gd --log-file .godot/iron_sword_render60.log -- --capture
& $godotExe --path . --script res://tests/iron_sword_animation.gd --log-file .godot/iron_sword_render30.log -- --fps30 --capture
```

Godot 4.7.2.stable.official.ed1daf0bf／Windows、物理60Hz、1プロセスずつ実行。描画1152×720・Compatibility／GTX1080。ヘッドレス2177、実描画60上限2162／30上限1175 assertionsでPASS・終了0（観測tick数で件数変動）。画像は`.godot/iron_sword_attack_方向_0〜2_60/30.png`、Guardも保存。中央・倍率・各コマ・カメラ同期は確認、手元の隙間は上記の要レビュー。

最終コードエラーと環境ERRORは区別する。証明書ストア／エディター設定保存のERRORは従来の実行環境によるもの。ユーザーF5／F6、実機パッド、長時間性能、複雑地形、多数・大型敵は未実行。素材の作者／ライセンスは未報告のままASSET_REGISTERへ登録し、公開承認とはしない。旧16px素材は保持、コミット／プッシュは未実行。

既存回帰9種類もすべてヘッドレスPASS・終了0：m05_animations、m05_animation_transitions、m07_chain、m07_combo、m08_defense、m08_guard_sprite、m09_enemy_dash、weapon_sweep、player_damage_visual。ログは`.godot/iron_sword_reg_*.log`と`iron_sword_damage.log`、一覧は`iron_sword_results.json`（新規ヘッドレス／被弾の単独実行分はそれぞれのログ）。最終SCRIPT ERROR／Parse Error／SHADER ERRORなし。保護対象ソースと画像はHEADとのdiffなし。
