param(
    [ValidateSet('baseline','capture','smoke','regression')][string]$Mode = 'capture',
    [string]$GodotExe = 'D:\Game\Godot\Godot_v4.7.2-stable_win64_console.exe'
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path -Parent $PSScriptRoot
Push-Location $taskRoot
try {
    $taskTests = if ($Mode -eq 'regression') { @('m02_movement','m03_jump','m04_camera','m04_occlusion','m09_startup') } else { @('m10_rebuild_composition') }
    $taskResults = @()
    foreach ($taskTest in $taskTests) {
        $taskLog = ".godot/m10_rebuild_${Mode}_${taskTest}.log"
        $taskArgs = @('--path','.', '--quit-after','7200','--log-file', ".godot/m10_rebuild_${Mode}_${taskTest}_engine.log", '--script', "res://tests/$taskTest.gd")
        if ($Mode -in @('smoke','regression')) { $taskArgs = @('--headless','--fixed-fps','60') + $taskArgs }
        if ($Mode -eq 'baseline') { $taskArgs += @('--','--baseline-only') }
        if ($Mode -eq 'smoke') { $taskArgs += @('--','--headless-check') }
        & $GodotExe @taskArgs *> $taskLog
        $taskExit = $LASTEXITCODE
        $taskContents = Get-Content -LiteralPath $taskLog -Raw
        $taskScriptError = $taskContents -match 'SCRIPT ERROR|Parse Error|SHADER ERROR'
        $taskResults += @{test=$taskTest; exit_code=$taskExit; script_error=$taskScriptError; log=$taskLog}
        Write-Output "$taskTest : exit $taskExit; script error $taskScriptError"
        $taskCompleted = if ($Mode -eq 'regression') { $taskContents -match 'PASS' } else { $taskContents -match 'checks; failures: \[\]' }
        if ($taskExit -ne 0 -or $taskScriptError -or !$taskCompleted) { throw "Validation failed: $taskLog" }
    }
    $taskResults | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath "docs/measurements/m10_rebuild_${Mode}_results.json"
} finally {
    Pop-Location
}
