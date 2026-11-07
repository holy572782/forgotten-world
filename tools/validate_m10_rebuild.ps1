param(
    [ValidateSet('baseline','capture','smoke','regression','relief','relief_regression')][string]$Mode = 'relief',
    [string]$GodotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Push-Location $taskRoot
try {
    $taskRegression = $Mode -in @('regression','relief_regression')
    $taskTests = if ($taskRegression) { @('m02_movement','m03_jump','m04_camera','m04_occlusion','m09_startup') } elseif ($Mode -eq 'relief') { @('m10_rebuild_relief') } else { @('m10_rebuild_composition') }
    if ($Mode -eq 'relief_regression') { $taskTests += 'm10_wind_hills' }
    $taskResults = @()
    foreach ($taskTest in $taskTests) {
        $taskLog = ".godot/m10_rebuild_${Mode}_${taskTest}.log"
        $tickLimit = if ($taskTest -eq 'm10_wind_hills') { '60000' } else { '7200' }
        $taskArgs = @('--path','.', '--quit-after',$tickLimit,'--log-file', ".godot/m10_rebuild_${Mode}_${taskTest}_engine.log", '--script', "res://tests/$taskTest.gd")
        if ($Mode -eq 'smoke' -or $taskRegression) { $taskArgs = @('--headless','--fixed-fps','60') + $taskArgs }
        if ($Mode -eq 'baseline') { $taskArgs += @('--','--baseline-only') }
        if ($Mode -eq 'smoke') { $taskArgs += @('--','--headless-check') }
        if ($taskTest -eq 'm10_wind_hills') {
            $taskArgs += @('--','--fast')
            # This legacy fixture has a fixed report path. Preserve the original audit bytes.
            $historicalReport = Join-Path $taskRoot 'docs/measurements/m10_wind_hills_fast.json'
            $historicalBytes = [IO.File]::ReadAllBytes($historicalReport)
            try {
                & $GodotExe @taskArgs *> $taskLog
                $taskExit = $LASTEXITCODE
            } finally {
                [IO.File]::WriteAllBytes($historicalReport,$historicalBytes)
            }
        } else {
            & $GodotExe @taskArgs *> $taskLog
            $taskExit = $LASTEXITCODE
        }
        $taskContents = Get-Content -LiteralPath $taskLog -Raw
        $taskScriptError = $taskContents -match 'SCRIPT ERROR|Parse Error|SHADER ERROR'
        $taskCompleted = if ($taskTest -eq 'm10_wind_hills') {
            $taskContents -match '(?m)^M10 \d+ checks; failures 0\s*$'
        } elseif ($taskRegression) {
            $taskContents -match 'PASS'
        } else {
            $taskContents -match 'checks; failures: \[\]'
        }
        $taskResults += @{test=$taskTest; exit_code=$taskExit; script_error=$taskScriptError; completed=$taskCompleted; log=$taskLog}
        Write-Output "$taskTest : exit $taskExit; completed $taskCompleted; script error $taskScriptError"
        if ($taskExit -ne 0 -or $taskScriptError -or !$taskCompleted) { throw "Validation failed: $taskLog" }
    }
    $taskResults | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "docs/measurements/m10_rebuild_${Mode}_results.json"
} finally {
    Pop-Location
}
