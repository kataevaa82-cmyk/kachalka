# Recreate native recordings without touching the player's saves.
$ErrorActionPreference = 'Stop'
$marketingRoot = Split-Path $PSScriptRoot -Parent
$repoRoot = Split-Path $marketingRoot -Parent
$stageRoot = Join-Path $marketingRoot '_work/capture_game'
$gameRoot = Join-Path $repoRoot 'godot'
New-Item -ItemType Directory -Force -Path $stageRoot | Out-Null
foreach ($item in @('project.godot','icon.svg','assets','data','scripts','scenes')) {
    Copy-Item -LiteralPath (Join-Path $gameRoot $item) -Destination $stageRoot -Recurse -Force
}
New-Item -ItemType Directory -Force -Path (Join-Path $stageRoot '.godot') | Out-Null
foreach ($item in @('imported','global_script_class_cache.cfg','uid_cache.bin')) {
    Copy-Item -LiteralPath (Join-Path $gameRoot ".godot/$item") -Destination (Join-Path $stageRoot '.godot') -Recurse -Force
}
$utf8 = [Text.UTF8Encoding]::new($false)
$projectPath = Join-Path $stageRoot 'project.godot'
$projectText = [IO.File]::ReadAllText($projectPath).Replace('config/name="КАЧАЛКА"','config/name="KachalkaMarketingCapture"')
[IO.File]::WriteAllText($projectPath, $projectText, $utf8)
$statePath = Join-Path $stageRoot 'scripts/autoload/game_state.gd'
[IO.File]::WriteAllText($statePath, [IO.File]::ReadAllText($statePath).Replace("`tload_game()", "`t# Fresh capture state."), $utf8)
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'capture.gd'),(Join-Path $PSScriptRoot 'capture.tscn') -Destination $stageRoot -Force
# capture.gd uses the workspace's C:/kach path for screenshot outputs.
$capturePath = Join-Path $stageRoot 'capture.gd'
$portableRoot = $marketingRoot.Replace('\','/')
[IO.File]::WriteAllText($capturePath, [IO.File]::ReadAllText($capturePath).Replace('C:/kach/marketing', $portableRoot), $utf8)
$godotExe = (Get-Command godot_console).Source
foreach ($lang in @('ru','en')) {
    $moviePath = Join-Path $marketingRoot "_work/gameplay_$lang.avi"
    $args = @('--path', ('"' + $stageRoot + '"'), '--resolution', '1280x720', '--position', '-3000,-3000', '--disable-vsync', '--fixed-fps', '30', '--write-movie', ('"' + $moviePath + '"'), 'res://capture.tscn', '--', $lang)
    $process = Start-Process -FilePath $godotExe -ArgumentList $args -WindowStyle Hidden -PassThru
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Recording failed: $lang" }
}
# Emulate a touchscreen only inside the disposable capture project.
Get-ChildItem -LiteralPath (Join-Path $stageRoot 'scripts') -Recurse -Filter '*.gd' | ForEach-Object {
    $text = [IO.File]::ReadAllText($_.FullName).Replace('DisplayServer.is_touchscreen_available()', 'true')
    [IO.File]::WriteAllText($_.FullName, $text, $utf8)
}
foreach ($lang in @('ru','en')) {
    $args = @('--path', ('"' + $stageRoot + '"'), '--resolution', '1280x720', '--position', '-3000,-3000', '--disable-vsync', '--fixed-fps', '30', 'res://capture.tscn', '--', $lang, 'mobile')
    $process = Start-Process -FilePath $godotExe -ArgumentList $args -WindowStyle Hidden -PassThru
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "Mobile capture failed: $lang" }
}
python (Join-Path $PSScriptRoot 'build_videos.py')
python (Join-Path $PSScriptRoot 'build_preview.py')
python (Join-Path $PSScriptRoot 'validate_media.py')
