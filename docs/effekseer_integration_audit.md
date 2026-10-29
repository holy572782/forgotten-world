# Effekseer Godot 4プラグイン導入（2026-10-29、ADR-041）

## 目的・範囲・受入条件

ユーザーの「ダウンロード後このゲームに組み込んで利用できるようにする」依頼に対応。Issueは未作成。単一目的は、現在のGodotでエフェクトをインポートし再生できる状態にすること。

対象は公式 `addons/effekseer/`、`project.godot` の有効化／既定値、公式最小サンプル、独立F6プレビューと導入検査、出典／仕様／進捗記録。受入条件はエディターのインポート成功、ネイティブクラス登録、Compatibilityでの実描画・停止／再生・終了／解放、既存mainの起動／戦闘維持。依存DLLの互換性とエディター再起動が導入時の注意点。

既存入力・戦闘・斬撃／火花／SE・敵AI・カメラ・メインシーン・描画方式は変更していない。M09は完了（試作範囲・基本戦闘）を維持。既存追加改善のF5待ちも維持し、M10は別指示待ち。

## 配布元と構成

- [公式安定版1.80.5.1](https://github.com/effekseer/EffekseerForGodot4/releases/tag/1.80.5.1) を採用。Godot 4.7向けスクリプト修正あり。新しい1.80.7はプレリリースのため今回は選ばなかった。
- ZIPとhash／ソースリビジョンは `addons/effekseer/UPSTREAM.md`。MIT LICENSEを保持。コード・バイナリは配布物とバイト一致、アイコンの `.import` メタデータと生成UIDのみGodot側で更新。
- 約153MiB、他OS用も配布構成どおり保持。最終対象OSの決定ではない。Windows x86_64以外・エクスポート済み実行ファイルは未検証。
- `project.godot` の `[editor_plugins]` で有効化。GDExtensionはファイルスキャンで自動検出。Autoloadは不要。
- `[effekseer]` は配布版既定値のInstance 4000／Square 16000／Draw 256、同梱Sound Script、Gamma（color_space=0）。既存のgl_compatibilityを維持。
- 公式サンプルは同一リビジョンの `Simple_Sprite_BillBoard.efkefc` と `Texture/Particle01.png` のみ。出典・hash・MIT LICENSEは `assets/effects/effekseer_sample/`、素材台帳にも記録。自作素材と混同しない。

## Godotでの使い方

1. Godotエディターを開いている場合は、実行をF8で止め、プロジェクトを一度閉じて開き直す。ネイティブGDExtensionの検出と初回インポートを待つ。
2. プロジェクト設定 → プラグインで **Effekseer for Godot4 / 1.80.5.1** が有効であることを確認。
3. `scenes/tests/effekseer_preview.tscn` を開き **F6**。暗い背景に色付きの粒が表示され、3秒ごとに再生する。Jまたは「再生」ボタンでも再生、F8で停止。F5の入口はmainのまま。
4. 自作の `.efkefc` を `assets/effects/` 以下へ置く。Texture／Model／Material／Sound等も、エフェクトが参照する相対配置を崩さずコピーする。検査用素材へ上書きしない。
5. 3Dフィールドでは **EffekseerEmitter3D** をNode3D配下に追加し、Inspectorの **Effect** にefkefcを割り当てる。2D UI用途はEffekseerEmitter2D。3Dのスプライトキャラクターもフィールド上では3Dエミッターを使用する。
6. 開始時に再生するならAutoplay、単発後にノードを解放するならAutofreeを有効にする。コードで開始する場合はAutoplayをOFFにして、既存イベントから `play()`、中断時は `stop()`。プレビューは再生ボタンのためAutofreeをOFFにしている。
7. 大きさはまずefkefc選択 → インポートのScale → 再インポートで調整する。サンプルプレビューはノード倍率0.3。素材によって拡大継承の挙動が違うため、素材ごとに確認する。

表示のみの単発再生例（Node3Dのスクリプト）：

```gdscript
func show_effect(effect: EffekseerEffect, world_position: Vector3) -> void:
    var emitter := EffekseerEmitter3D.new()
    emitter.effect = effect
    emitter.autoplay = false
    emitter.autofree = true
    add_child(emitter)
    emitter.global_position = world_position
    emitter.play()
```

ループ素材は自然終了しないので所有者側で停止／解放する。演出の再生を新たな命中・HP計算の根拠にしない。今回、既存攻撃／命中イベントへの割当は行っていない。

Effekseer制作ツール自体は今回未導入。既存ツールはプラグインと互換性のある出力で使用する。「Open in Effekseer」はGodotのエディター設定 → Effekseer → Editor Pathへ実際のツールパスを指定して使う。GPU粒子、歪み、独自材質、エフェクト内音声、2Dの実描画、長時間負荷は未検証。

公式資料: [使い方](https://effekseer.github.io/Help_Godot/v4/ja/how-to-use.html)、[API](https://effekseer.github.io/Help_Godot/v4/ja/api-reference.html)。API資料には古い型表記もあるため実際のInspector／導入版を優先する。

## 検査と再現

Godot `4.7.2.stable.official.ed1daf0bf`、Windows x86_64、Compatibility / OpenGL 3.3 / GTX 1080。

| 検査 | 結果 |
|---|---|
| headless editor import | 成功・終了0 |
| effekseer_integration（実描画60fps上限） | 13項目PASS・終了0 |
| m09_startup（実描画） | PASS・終了0。既定敵の攻撃、左攻撃／右防御、GUI切替／reset |
| enemy_jump_strike（実描画60fps上限） | 543項目PASS・終了0 |

導入検査はネイティブ2D／3D登録、Singleton、設定、efkefc／テクスチャ依存、Autoplay、stop／再生、描画差分、自然終了1通知、Autofreeを確認。960×600、描画差分3135サンプル（乱数で変動）。`.godot/effekseer_preview.png` を目視済み。

検査プロセスだけAPPDATA／LOCALAPPDATAをworkspace内へ分離し、個人設定とシェーダーキャッシュを保存した。通常の環境ではその変更は不要。初回検査コードのWeakRef型推論を明示型へ修正。通常環境変数での初回描画ではsandbox外のシェーダーキャッシュ保存エラーが2件出たが、保存先を分離して再実行後はエラーなし。プラグインのコード変更は不要だった。

プロジェクト直下のPowerShellで、Godotは1プロセスずつ実行する：

```powershell
$godotExe = 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
# Codexの制限環境内で検証する場合のみ設定（このプロセス内）
$env:APPDATA = Join-Path $PWD '.godot/effekseer_runtime_appdata'
$env:LOCALAPPDATA = Join-Path $PWD '.godot/effekseer_runtime_localappdata'
& $godotExe --headless --path . --editor --import
& $godotExe --path . --resolution 960x600 --script res://tests/effekseer_integration.gd
& $godotExe --path . --script res://tests/m09_startup.gd
& $godotExe --path . --script res://tests/enemy_jump_strike.gd
```

各コマンド後に `$LASTEXITCODE` と出力を確認。ログ／画像は `.godot/effekseer_*.log`／PNG（Git対象外）。最終editor importも終了0、最終import／実描画検査／回帰ログにエラー・警告なし、`git diff --check` 合格。ユーザーのエディター／F6／F5操作の受入は未実行。次はF6で表示を確認し、実際に使う演出と再生イベントを別途指定する。
