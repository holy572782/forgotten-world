# 炎単体1の命中演出

ユーザー指定「炎単体1」＝提供された `RPGツクールMZeffects/FireOne1.efkefc`。`fire_one1.efkefc` は原本とバイト一致する無加工コピー。依存する `Texture/Fog.png`、`Particle100.png`、`ParticleAlpha.png` も無加工で相対配置を保持する。

ゲーム側で実際にHPを減らしたMAGIC弾の命中位置にだけ再生。通常／Guardとも同じデータ・魔導士の倍率0.3（2026-10-30、ADR-045で旧0.06の5倍へ拡大）、Fire2・volume -12dB／pitch1.0。Projectileとは別のノードが完走し、自然終了で解放する。壁・射程／寿命終了には出さず、物理矢に見た目から魔法属性を推測して付けない。

出典・許諾：ユーザー提供のRPGツクールMZ素材。今回の指定によるローカル試作への使用。作者・Godot利用／再配布条件の詳細は未確認として素材台帳へ記録し、MIT等の独自許諾を付けない。原本を変更しない。再コピー手順は `tools/prepare_mage_fire_effects.ps1`。
