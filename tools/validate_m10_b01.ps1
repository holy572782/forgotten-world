param(
    [ValidateSet('before', 'after', 'before_stations', 'after_stations', 'views', 'smoke30', 'regression')]
    [string]$Mode = 'after',
    [string]$GodotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
Push-Location -LiteralPath (Split-Path $PSScriptRoot -Parent)
try {
    if ($Mode -eq 'regression') {
        & $GodotExe --headless --fixed-fps 60 --path . --script res://tests/m04_occlusion.gd --log-file .godot/m10_b01_m04.log
        if ($LASTEXITCODE -ne 0) { throw 'M04 occlusion failed' }
		$resultPath = Join-Path (Get-Location) 'docs/measurements/m10_wind_hills_fast.json'
		$savedResult = [IO.File]::ReadAllBytes($resultPath)
		try {
			& $GodotExe --headless --fixed-fps 60 --path . --script res://tests/m10_wind_hills.gd --log-file .godot/m10_b01_m10.log -- --fast
			Copy-Item -LiteralPath $resultPath -Destination docs/measurements/m10_b01_m10_regression.json
		} finally {
			[IO.File]::WriteAllBytes($resultPath, $savedResult)
		}
    } else {
        $arguments = @('--path', '.', '--script', 'res://tests/m10_b01_entrance.gd', '--log-file', ".godot/m10_b01_$Mode.log")
        if ($Mode -eq 'views') { $arguments = @('--fixed-fps', '60') + $arguments }
        $arguments += '--'
        $arguments += $(if ($Mode -like 'before*') { '--before' } else { '--after' })
        if ($Mode -eq 'views') { $arguments += @('--capture', '--fast', '--views-only', '--variants', '--details') }
        elseif ($Mode -eq 'smoke30') { $arguments += @('--performance', '--30') }
        elseif ($Mode -like '*_stations') { $arguments += @('--performance', '--stations-only') }
        else { $arguments += @('--performance', '--capture') }
        & $GodotExe @arguments
    }
    if ($LASTEXITCODE -ne 0) { throw "Godot failed with exit $LASTEXITCODE" }
} finally {
    Pop-Location
}
