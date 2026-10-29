param([string]$EffekseerExe = "$PSScriptRoot/../.godot/effekseer_authoring/tool/Effekseer1.80.5Win/Tool/bin/Effekseer.exe")
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath("$PSScriptRoot/..")
$tool=(Resolve-Path -LiteralPath $EffekseerExe).Path
[void][Reflection.Assembly]::LoadFrom((Join-Path (Split-Path $tool) 'EffekseerCore.dll'))
$decoder=[Effekseer.Core].Assembly.GetType('Effekseer.IO.EfkEfcXml').GetMethod('Decompress',[Reflection.BindingFlags]'Public,NonPublic,Static')
function Read-EffectXml([string]$path) {
    $bytes=[IO.File]::ReadAllBytes($path)
    for($pos=8;$pos -lt $bytes.Length;) {
        $chunk=[Text.Encoding]::ASCII.GetString($bytes,$pos,4)
        $length=[BitConverter]::ToInt32($bytes,$pos+4)
        if($chunk -eq 'EDIT') {
            $data=[byte[]]::new($length)
            [Array]::Copy($bytes,$pos+8,$data,0,$length)
            return $decoder.Invoke($null,[object[]]@(,$data))
        }
        $pos+=8+$length
    }
    throw "Missing edit data: $path"
}
$reference=Join-Path $projectRoot 'RPGツクールMZeffects'
$hit=Join-Path $projectRoot 'assets/effects/mage_fire_hit'
$circle=Join-Path $projectRoot 'assets/effects/mage_circle_fire'
$source=Join-Path $projectRoot 'assets/source/effects/mage_circle_fire'
New-Item -ItemType Directory -Force "$hit/Texture","$circle/Texture",$source | Out-Null
# Preserve the exact user-selected FireOne1 effect and its own relative dependencies.
Copy-Item -LiteralPath "$reference/FireOne1.efkefc" -Destination "$hit/fire_one1.efkefc"
$hitXml=Read-EffectXml "$reference/FireOne1.efkefc"
foreach($texture in ($hitXml.SelectNodes('//ColorTexture') | ForEach-Object InnerText | Sort-Object -Unique)) {
    if($texture) { Copy-Item -LiteralPath (Join-Path $reference $texture) -Destination (Join-Path $hit $texture) }
}
Copy-Item -LiteralPath "$reference/Texture/HexCircle.png" -Destination "$circle/Texture/HexCircle.png"
$referenceXml=Read-EffectXml "$reference/FireAll3.efkefc"
$referenceNode=$referenceXml.SelectSingleNode('//Node[Name="HexCircleDown"]')
if($null -eq $referenceNode) { throw 'FireAll3 floor circle not found' }
# Reuse the selected texture; remove the reference's elevated/flying layers.
# Bake X=90 into the fixed sprite, rather than rotating the native emitter.
$xml=@"
<?xml version="1.0" encoding="utf-8"?>
<EffekseerProject><Root><Name>Root</Name><Children><Node><Name>FireAll3 floor circle</Name>
<CommonValues><MaxGeneration><Value>1</Value></MaxGeneration><Life><Center>60000</Center><Max>60000</Max><Min>60000</Min></Life></CommonValues>
<RotationValues><Type>0</Type><Fixed><Rotation><X>90</X></Rotation></Fixed></RotationValues>
<RendererCommonValues><ColorTexture>../../../effects/mage_circle_fire/Texture/HexCircle.png</ColorTexture><AlphaBlend>1</AlphaBlend><ZTest>True</ZTest><ZWrite>False</ZWrite><FadeInType>1</FadeInType><FadeIn><Frame>7</Frame></FadeIn></RendererCommonValues>
<DrawingValues><Type>2</Type><Sprite><Billboard>2</Billboard><ColorAll_Fixed><R>255</R><G>255</G><B>255</B><A>255</A></ColorAll_Fixed><Position>1</Position><Position_Fixed_LL><X>-0.5</X><Y>-0.5</Y></Position_Fixed_LL><Position_Fixed_LR><X>0.5</X><Y>-0.5</Y></Position_Fixed_LR><Position_Fixed_UL><X>-0.5</X><Y>0.5</Y></Position_Fixed_UL><Position_Fixed_UR><X>0.5</X><Y>0.5</Y></Position_Fixed_UR></Sprite></DrawingValues><Children/></Node></Children></Root><ToolVersion>1.80.5</ToolVersion><Version>3</Version><StartFrame>0</StartFrame><EndFrame>120</EndFrame><IsLoop>True</IsLoop></EffekseerProject>
"@
[IO.File]::WriteAllText("$source/mage_circle_fire.efkproj",$xml)
$arguments=@('-cui','-in',('"'+$source+'/mage_circle_fire.efkproj"'),'-o',('"'+$circle+'/mage_circle_fire.efkefc"'))
$process=Start-Process -FilePath $tool -ArgumentList $arguments -WorkingDirectory (Split-Path $tool) -WindowStyle Hidden -Wait -PassThru
if($process.ExitCode -ne 0 -or -not (Test-Path "$circle/mage_circle_fire.efkefc")) { throw 'Circle export failed' }
foreach($sound in @('Magic1','Fire2')) {
    Copy-Item -LiteralPath "$projectRoot/RPGツクールMZのaudio/se/$sound.ogg" -Destination "$projectRoot/assets/audio/sfx/mz_$($sound.ToLowerInvariant()).ogg"
}
Write-Output 'Prepared floor circle, unchanged FireOne1 and its textures, Magic1 and Fire2.'
