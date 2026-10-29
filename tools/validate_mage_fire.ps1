param([switch]$ImportOnly)
$ErrorActionPreference='Stop'
$projectRoot=[IO.Path]::GetFullPath("$PSScriptRoot/..")
$validationRoot=Join-Path $projectRoot '.godot/mage_fire_validation'
# Separate native-library copy avoids colliding with the user's open editor.
New-Item -ItemType Directory -Force $validationRoot | Out-Null
foreach($folder in @('assets','resources','scenes','scripts','tests','RPGツクールMZeffects','RPGツクールMZのaudio','画像フォルダ')) {
    Copy-Item -LiteralPath (Join-Path $projectRoot $folder) -Destination $validationRoot -Recurse -Force
}
Copy-Item -LiteralPath "$projectRoot/project.godot" -Destination $validationRoot -Force
$pluginDir=Join-Path $validationRoot 'addons/effekseer'
New-Item -ItemType Directory -Force $pluginDir,"$pluginDir/bin/windows" | Out-Null
Get-ChildItem -LiteralPath "$projectRoot/addons/effekseer" | Where-Object Name -ne 'bin' | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $pluginDir -Recurse -Force }
Copy-Item -LiteralPath "$projectRoot/addons/effekseer/bin/windows/libeffekseer.x86_64.dll" -Destination "$pluginDir/bin/windows" -Force
$env:APPDATA=Join-Path $projectRoot '.godot/mage_runtime_appdata'
$env:LOCALAPPDATA=$env:APPDATA
$godotExe='D:/Game/Godot/Godot_v4.7.2-stable_win64_console.exe'
& $godotExe --headless --path $validationRoot --editor --import --log-file "$projectRoot/.godot/mage_fire_validation_import.log" *> "$projectRoot/.godot/mage_fire_validation_import_console.log"
if($LASTEXITCODE -ne 0) { throw 'Validation import failed' }
if(Select-String -Path "$projectRoot/.godot/mage_fire_validation_import_console.log" -Pattern 'ERROR|SCRIPT ERROR|Parse Error') { throw 'Import diagnostic errors' }
if($ImportOnly) { Write-Output 'Isolated import passed'; exit }
& $godotExe --path $validationRoot --script res://tests/mage_fire_feedback.gd --log-file "$projectRoot/.godot/mage_fire_feedback60.log"
exit $LASTEXITCODE
