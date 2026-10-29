# Effekseer公式サンプル（導入検証用）

`Simple_Sprite_BillBoard.efkefc` と依存する `Texture/Particle01.png` のみを、公式Godot 4プラグインの同一リビジョンから無加工取得。内部参照に合わせファイル名・相対配置は上流どおり保持する。

- 出典: https://github.com/effekseer/EffekseerForGodot4/tree/29361d13afe24eb8acacf44695e8b8ac3f1aa33e/Demo/effects/samples
- 許諾: 同リポジトリルートのMIT LICENSEを同梱。Demo/READMEの別ライセンス指定は `shared/models/**` のみであり、今回その素材は含めていない。
- efkefc SHA256: `adba0715467d9be6021a1ea7c0b7ccfd9e648367b6789956fbb448e8f0898dfe`
- PNG SHA256: `b1346d2bfafa6e783661453680b282edc6bc0e0b85711414b9914aac03a3a881`

ゲームの正式な演出素材には未割当。`scenes/tests/effekseer_preview.tscn` を開きF6で再生確認する。自作エフェクトは別フォルダーへ置き、依存テクスチャ・モデル・材質・音の相対構造と利用条件を保持する。
