param(
    [string]$EffekseerExe = "$PSScriptRoot/../.godot/effekseer_authoring/tool/Effekseer1.80.5Win/Tool/bin/Effekseer.exe",
    [string]$GodotExe = 'D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath("$PSScriptRoot/..")
$sourceDir = Join-Path $projectRoot 'assets/source/effects/mage_circle'
$outputDir = Join-Path $projectRoot 'assets/effects/mage_circle'
New-Item -ItemType Directory -Force $sourceDir,"$outputDir/textures" | Out-Null
# Original geometric marks only; no external fonts, symbols or image assets.
$outer = [Text.StringBuilder]::new()
[void]$outer.Append('<circle cx="256" cy="256" r="238"/><circle cx="256" cy="256" r="224"/><circle cx="256" cy="256" r="190"/>')
for ($i=0; $i -lt 16; $i++) {
    $angle = $i*22.5
    [void]$outer.Append("<g transform='rotate($angle 256 256)'><path d='M250 49 L250 65 L262 65 L262 57 M256 65 L256 77'/><path d='M253 24 L259 24'/></g>")
}
for ($i=0; $i -lt 4; $i++) {
    $angle=$i*90
    [void]$outer.Append("<g transform='rotate($angle 256 256)'><path d='M256 83 L270 99 L256 115 L242 99 Z'/></g>")
}
$inner = '<circle cx="256" cy="256" r="148"/><path d="M256 108 L384.17 330 L127.83 330 Z M256 404 L127.83 182 L384.17 182 Z"/><circle cx="256" cy="256" r="62"/><path d="M256 208 L304 256 L256 304 L208 256 Z M256 233 L256 279 M233 256 L279 256"/>'
foreach ($part in @(@('outer',$outer.ToString()),@('inner',$inner))) {
    $svg = "<svg xmlns='http://www.w3.org/2000/svg' width='512' height='512' viewBox='0 0 512 512'><g fill='none' stroke='white' stroke-width='5' stroke-linecap='square' stroke-linejoin='miter'>$($part[1])</g></svg>"
    [IO.File]::WriteAllText("$sourceDir/circle_$($part[0]).svg",$svg)
}
& $GodotExe --headless --path $projectRoot --script res://tools/rasterize_mage_circle.gd
if ($LASTEXITCODE -ne 0) { throw 'SVG rasterization failed' }
function New-CircleNode([string]$name,[string]$texture,[double]$spin) {
    $spinText=$spin.ToString([Globalization.CultureInfo]::InvariantCulture)
    return @"
<Node><Name>$name</Name><CommonValues><MaxGeneration><Value>1</Value></MaxGeneration><Life><Center>60000</Center><Max>60000</Max><Min>60000</Min></Life></CommonValues>
<RotationValues><Type>1</Type><PVA><Rotation><Z><Center>0</Center><Max>0</Max><Min>0</Min></Z></Rotation><Velocity><Z><Center>$spinText</Center><Max>$spinText</Max><Min>$spinText</Min></Z></Velocity></PVA></RotationValues>
<RendererCommonValues><ColorTexture>../../../effects/mage_circle/textures/$texture.png</ColorTexture><AlphaBlend>1</AlphaBlend><ZTest>True</ZTest><ZWrite>False</ZWrite><FadeInType>1</FadeInType><FadeIn><Frame>7</Frame></FadeIn></RendererCommonValues>
<DrawingValues><Type>2</Type><Sprite><Billboard>2</Billboard><ColorAll>0</ColorAll><ColorAll_Fixed><R>255</R><G>255</G><B>255</B><A>255</A></ColorAll_Fixed><Position>1</Position><Position_Fixed_LL><X>-0.5</X><Y>-0.5</Y></Position_Fixed_LL><Position_Fixed_LR><X>0.5</X><Y>-0.5</Y></Position_Fixed_LR><Position_Fixed_UL><X>-0.5</X><Y>0.5</Y></Position_Fixed_UL><Position_Fixed_UR><X>0.5</X><Y>0.5</Y></Position_Fixed_UR></Sprite></DrawingValues><Children/></Node>
"@
}
$nodes=(New-CircleNode 'Outer runes' 'circle_outer' 0)+(New-CircleNode 'Counter rotating seal' 'circle_inner' -0.35)
$xml = "<?xml version='1.0' encoding='utf-8'?><EffekseerProject><Root><Name>Root</Name><Children>$nodes</Children></Root><ToolVersion>1.80.5</ToolVersion><Version>3</Version><StartFrame>0</StartFrame><EndFrame>120</EndFrame><IsLoop>True</IsLoop></EffekseerProject>"
[IO.File]::WriteAllText("$sourceDir/mage_circle.efkproj",$xml)
$resolvedTool=(Resolve-Path -LiteralPath $EffekseerExe).Path
$toolArguments = @('-cui','-in',('"'+$sourceDir+'/mage_circle.efkproj"'),'-o',('"'+$outputDir+'/mage_circle.efkefc"'))
$toolProcess = Start-Process -FilePath $resolvedTool -ArgumentList $toolArguments -WorkingDirectory (Split-Path $resolvedTool) -WindowStyle Hidden -Wait -PassThru
if ($toolProcess.ExitCode -ne 0) { throw "Effekseer exited with $($toolProcess.ExitCode)" }
if (-not (Test-Path "$outputDir/mage_circle.efkefc")) { throw 'Effekseer output missing' }
$header=[IO.File]::ReadAllBytes("$outputDir/mage_circle.efkefc")
if ([Text.Encoding]::ASCII.GetString($header,0,4) -ne 'EFKE') { throw 'Invalid Effekseer container' }
Write-Output "Created $outputDir/mage_circle.efkefc"
