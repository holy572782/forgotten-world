# 魔法陣の編集元

`mage_circle.efkproj` はEffekseerが読めるXML形式の制作元。`circle_outer.svg`／`circle_inner.svg` は独自のベクター原画。ゲーム用には `assets/effects/mage_circle/mage_circle.efkefc` と同フォルダー内のPNGを使用する。

Effekseerで直接編集する場合は、制作情報も含むゲーム用 `.efkefc` を開ける。XMLは同じ配列を再生成するための管理可能な原本として保持する。XMLのTexture参照はゲーム側のPNGへ相対参照するため、フォルダー構造を保持する。

再生成は `tools/create_mage_circle.ps1`。このスクリプトは本フォルダーのSVG／XMLとゲーム用PNG／efkefcを再生成するため、手動で編集した結果は先に別名で保存する。Effekseerアプリ自体はGit対象外の `.godot/effekseer_authoring/` に取得した作業用コピー。別のマシンでは公式1.80.5を用意して `-EffekseerExe` へ指定する。
