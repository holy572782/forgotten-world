param(
    [ValidateSet('headless', 'render', 'smoke30', 'views', 'regression')]
    [string]$Mode = 'headless',
    [string]$GodotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location -LiteralPath $projectRoot
try {
    if ($Mode -eq 'regression') {
        $tests = @('m02_movement', 'm03_jump', 'm04_camera', 'm04_occlusion', 'm07_chain', 'm08_defense', 'm09_startup')
        foreach ($test in $tests) {
            & $GodotExe --headless --fixed-fps 60 --path . --script "res://tests/$test.gd" --log-file ".godot/m10_regression_$test.log"
            if ($LASTEXITCODE -ne 0) { throw "$test failed with exit $LASTEXITCODE" }
        }
    } elseif ($Mode -eq 'headless') {
        & $GodotExe --headless --fixed-fps 60 --path . --script res://tests/m10_wind_hills.gd --log-file .godot/m10_traverse_fast.log -- --fast
    } elseif ($Mode -eq 'render') {
        & $GodotExe --path . --script res://tests/m10_wind_hills.gd --log-file .godot/m10_render60.log -- --capture
    } elseif ($Mode -eq 'smoke30') {
        & $GodotExe --path . --script res://tests/m10_wind_hills.gd --log-file .godot/m10_render30.log -- --30 --smoke
    } else {
        & $GodotExe --fixed-fps 60 --path . --script res://tests/m10_views.gd --log-file .godot/m10_views.log -- --fast
    }
    if ($LASTEXITCODE -ne 0) { throw "Godot failed with exit $LASTEXITCODE" }
} finally {
    Pop-Location
}
