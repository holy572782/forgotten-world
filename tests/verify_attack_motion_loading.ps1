param(
    [string]$GodotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$probeRoot = Join-Path $projectRoot '.godot/attack_motion_loading_probe'
$cachePath = Join-Path $projectRoot '.godot/global_script_class_cache.cfg'
if (-not (Test-Path -LiteralPath $cachePath)) {
    throw 'Open/import the main project once before running this isolated cache test.'
}
# Copy only a disposable test project. Never remove or rewrite the main cache.
New-Item -ItemType Directory -Path $probeRoot -Force | Out-Null
foreach ($folder in @('scripts', 'resources', 'scenes', 'assets', 'tests')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $folder) -Destination $probeRoot -Recurse -Force
}
Copy-Item -LiteralPath (Join-Path $projectRoot 'project.godot') -Destination $probeRoot -Force
New-Item -ItemType Directory -Path (Join-Path $probeRoot '.godot') -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $projectRoot '.godot/imported') -Destination (Join-Path $probeRoot '.godot') -Recurse -Force
$cacheText = [IO.File]::ReadAllText($cachePath)
$classBlocks = [regex]::Matches($cacheText, '(?s)\{.*?\}') |
    ForEach-Object { $_.Value } |
    Where-Object { $_ -notmatch '"class": &"AttackMotionSettings"' }
$isolatedCache = 'list=[' + ($classBlocks -join ', ') + "]`n"
[IO.File]::WriteAllText((Join-Path $probeRoot '.godot/global_script_class_cache.cfg'), $isolatedCache, [Text.UTF8Encoding]::new($false))
$logPath = Join-Path $projectRoot '.godot/motion_loading_unregistered.log'
& $GodotExe --headless --path $probeRoot --script tests/attack_motion_loading.gd --log-file $logPath -- --expect-unregistered
$runExit = $LASTEXITCODE
$runLog = [IO.File]::ReadAllText($logPath)
if ($runExit -ne 0 -or $runLog -match 'SCRIPT ERROR|Parse Error|Compile Error|SHADER ERROR') {
    throw "Isolated loading check failed (exit $runExit). See $logPath"
}
Write-Output 'Isolated loading check passed without registering AttackMotionSettings.'
