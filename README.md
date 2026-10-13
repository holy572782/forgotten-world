> **2026-10-13更新**: システム先行で開発。Godot採用。詳細仕様 `docs/10_SYSTEM_SPEC_GODOT.md`、Codex順序 `docs/11_CODEX_IMPLEMENTATION_PLAN.md`、テスト `docs/12_TEST_PLAN.md`。

# 忘れられた世界の旅人 / The Last Fable

> オリジナル・幻想アクションアドベンチャー企画。版 `0.1.0`（2026-10-13）。**M00完了。Godot 4.7.2で起動・ヘッドレス読み込み・InputMapを確認済み。ゲームプレイは未実装です。**

## 一言でいうと
夢・記憶・願いが風景になる幻想世界「エルディア」を、白化から救う旅。2Dスプライトの登場人物と3D世界を組み合わせ、七つの試練を順不同に探索するアクションアドベンチャー。

## 最初に読む順番
1. `docs/00_PROJECT_CHARTER.md`：核となる企画と確定／仮／未決定の区別
2. `docs/01_WORLD_BIBLE.md`：世界のルールと設定
3. `docs/02_STORY_AND_CHARACTERS.md`：物語と登場人物
4. `docs/03_SEVEN_TRIALS.md`：七地域・七つの試練
5. `docs/04_GAME_DESIGN.md`：遊びとシステム
6. `AGENTS.md`：Codex・AI開発エージェントの作業ルール
7. `docs/05_PRODUCTION_RULES.md`：制作・アセット・著作権ルール
8. `docs/06_TECH_AND_GITHUB.md`：技術選定とGitHub導入

## ステータスの意味
- **合意済み**：この会話で採用した制作方針。変更はADRに記録。
- **企画案**：以前の提案に含まれるが詳細未承認、または新たに整理した案。
- **未決定**：推測で確定させない。

## 始め方
1. 新規プライベートGitHubリポジトリを作り、フォルダの中身を入れてコミット。
2. `docs/08_DECISIONS.md` と `docs/09_BACKLOG.md` を確認。
3. 使用エンジン（Godot／Unityなど）、発売プラットフォーム、画面解像度・目標fpsを決める。
4. 最小試作：草原一画面、2D主人公、3D地形、敵一体、攻撃ゲージ、回避、会話、残響。
5. Codexには`AGENTS.md`を読ませ、Issue単位の小さな変更を依頼。

## この資料の運用
重要な設定変更は `docs/08_DECISIONS.md` に理由を記載し、該当資料と同時更新。会話中に決まった内容も、**ファイルに追記してコミットするまではプロジェクトの正式な最新版ではありません**。

## M00：Godotプロジェクトの起動

- 対象：Godot 4.x。今回の検証版：`4.7.2.stable.official.ed1daf0bf`。
- 検証（2026-10-13）：ユーザーがF5で灰色の実行画面を確認。Codexがヘッドレス読み込み・60フレーム実行・InputMap全12アクション／30割り当ての合成入力検査に成功（終了コード0、エラー・警告なし）。記録は `docs/DEVELOPMENT_STATUS.md` を参照。
- `project.godot` と空の `scenes/main.tscn`（Node3D）の最小構成です。外部アセットやプラグインは不要です。
- Compatibilityレンダラーは起動用の仮設定、物理は仕様の初期値60 tick/sです。対応OSや最終描画方式を確定するものではありません。
- 既存資料に残る「エンジン未決定」については、Godot採用を決定したADR-003を優先します。

### エディターでの確認

1. Godot 4.xのプロジェクトマネージャーで、このフォルダの `project.godot` をインポートして開く。
2. プロジェクト設定 → Input Map（入力マップ）で、下表の12アクションとデッドゾーン `0.2` を確認する。
3. mainシーンを開いてF6、またはF5でプロジェクトを実行する。空の画面が表示され、エラーが出なければM00の起動確認完了。停止はF8を使用する。

空シーンなので移動・攻撃・ポーズ等の反応はありません。M01以降の地形・プレイヤー・カメラ・戦闘は未実装です。

### ヘッドレスでの確認（PowerShell）

プロジェクトのルートで実行します。`$godotExe` は実際に使用するGodot 4.x実行ファイルの絶対パスに置き換えてください。

```powershell
$godotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --version
& $godotExe --headless --path . --editor --quit
$LASTEXITCODE
& $godotExe --headless --path . --quit-after 60
$LASTEXITCODE
```

各終了コードが `0` で、出力に読み込みエラーがないことを確認します。再検証時は `--version` の正確な結果を記録してください。InputMap検査は `& $godotExe --headless --path . --script res://tests/m00_input_map.gd` で再実行できます。`.godot/` キャッシュは既存の `.gitignore` で除外されています。

### 入力の試作値

`docs/10_SYSTEM_SPEC_GODOT.md` 第2節に従い、キーボード・マウス・パッドを同じアクションに登録しています。全アクションのデッドゾーンは `0.2`。キーボードは物理キー位置を使用し、割り当てはInput Mapで変更できます。ゲーム中の再割り当て画面は後続です。

| アクション | キーボード／マウス | ゲームパッド |
|---|---|---|
| `move_left` | A／左矢印 | 左スティック左 |
| `move_right` | D／右矢印 | 左スティック右 |
| `move_up` | W／上矢印 | 左スティック上 |
| `move_down` | S／下矢印 | 左スティック下 |
| `jump` | Space | 南ボタン |
| `attack` | J／左クリック | 西ボタン |
| `dodge` | K／右クリック | 東ボタン |
| `camera_left` | Q | 右スティック左 |
| `camera_right` | E | 右スティック右 |
| `lock_on` | L | 右スティック押込 |
| `interact` | F | 北ボタン |
| `pause` | Esc | Start |

`lock_on`・`interact`も入力名のみ先に登録しています。斜め移動の正規化・アナログ強弱・UI操作中の攻撃抑止は、入力を利用する後続実装の範囲です。テスト計画のT01〜T15は今回の対象外で、未実行です。
