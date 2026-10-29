# FireAll3参照の床面魔法陣

ユーザー提供 `RPGツクールMZeffects/FireAll3.efkefc` の魔法陣（HexCircleDown）と同じ `Texture/HexCircle.png` を参照した、保持用のEffekseerエフェクト。提供PNGは無加工コピー。浮き上がる多段の円・他の炎／閃光は含めず、固定SpriteをX=90度の床面へ配置し、Game側の既存詠唱／発射fadeに合わせて保持・停止する。

原本XMLは `assets/source/effects/mage_circle_fire/`。再生成は `tools/prepare_mage_fire_effects.ps1`（公式Effekseer 1.80.5のCore DLLで提供データを読み、CLIで保存）。制作情報も含むefkefcなので同ツールで編集可能。旧オリジナルの魔法陣は別フォルダーに保持する。

ゲームではNativeの透明Viewportを床面のPlaneMeshへ投影し、魔導士本体の深度と分離する。256×256、実地面＋0.01m、直径2.8m、橙色、既存Y回転0.25rad/s・発射fade0.12秒。Circle Effect Is Floor=true。Light／衝突／影は追加しない。

出典・許諾：ユーザー提供のRPGツクールMZ素材。今回の指定によるローカル試作への使用。素材の作者・Godot利用／再配布条件の詳細は未確認として台帳へ記録し、独自の許諾やMITを付けない。原本フォルダーを変更しない。
