param([switch]$Restore)

$ErrorActionPreference = 'Stop'
$packages = Join-Path $env:LOCALAPPDATA 'Packages'
$candidates = @(
    (Join-Path $packages 'Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $packages 'Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
)
$settingsPath = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $settingsPath) { throw 'Windows Terminal settings.json was not found. Open Terminal once, then try again.' }

$backupPath = "$settingsPath.wsl-tmux-i3.bak"
if ($Restore) {
    if (-not (Test-Path $backupPath)) { throw "Backup not found: $backupPath" }
    Copy-Item $backupPath $settingsPath -Force
    Write-Host "Restored: $settingsPath"
    exit 0
}

# A single recoverable backup is deliberately preserved across repeated installs.
if (-not (Test-Path $backupPath)) { Copy-Item $settingsPath $backupPath }

try { $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json }
catch { throw "settings.json could not be parsed as JSON; the file was not changed. Details: $($_.Exception.Message)" }

$keys = @('ctrl+space', 'alt+enter', 'alt+space', 'alt+1', 'alt+2', 'alt+3', 'alt+4', 'alt+5', 'alt+6', 'alt+7', 'alt+8', 'alt+9',
    'alt+shift+left', 'alt+shift+down', 'alt+shift+up', 'alt+shift+right')
# Alt+Shift+1..9 must reach tmux as ESC plus the US-layout shifted symbol on
# every keyboard layout, so the keys are bound to explicit sendInput actions.
$moveSymbols = '!@#$%^&*('
$moves = 1..9 | ForEach-Object {
    [pscustomobject]@{ id = "User.wslTmuxI3.moveToWindow$_"; keys = "alt+shift+$_"; input = "$([char]27)$($moveSymbols[$_ - 1])" }
}
$existing = @($settings.keybindings) | Where-Object { $_ -and $keys -notcontains $_.keys -and $moves.keys -notcontains $_.keys }
$unbound = $keys | ForEach-Object { [pscustomobject]@{ id = 'unbound'; keys = $_ } }
$moveBindings = $moves | ForEach-Object { [pscustomobject]@{ id = $_.id; keys = $_.keys } }
$settings | Add-Member -Force NoteProperty keybindings @($existing + $unbound + $moveBindings)

$existingActions = @($settings.actions) | Where-Object { $_ -and $moves.id -notcontains $_.id }
$moveActions = $moves | ForEach-Object {
    [pscustomobject]@{ command = [pscustomobject]@{ action = 'sendInput'; input = $_.input }; id = $_.id }
}
$settings | Add-Member -Force NoteProperty actions @($existingActions + $moveActions)

$json = $settings | ConvertTo-Json -Depth 100
[IO.File]::WriteAllText($settingsPath, $json, [Text.UTF8Encoding]::new($false))
Write-Host "Windows Terminal shortcuts were released for tmux: $settingsPath"
Write-Host "Backup: $backupPath"
