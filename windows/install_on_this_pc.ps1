# Installs (or updates) the Windows app for the current user:
# copies the release build to %LOCALAPPDATA%\Programs\Sudhamrtam and makes
# Desktop and Start menu shortcuts. Sign-in and saved data stay in the
# user's app data folder, so updating keeps them.
#
# First build it (from the project folder):
#   flutter build windows --release --dart-define=API_BASE_URL=https://api.sudhamrtam.in
# Then run:
#   powershell -ExecutionPolicy Bypass -File windows\install_on_this_pc.ps1

$ErrorActionPreference = 'Stop'
$build = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release'
if (-not (Test-Path (Join-Path $build 'sudhamrtam_customer_app.exe'))) {
  throw "No release build in $build. Run flutter build windows --release first."
}

$target = Join-Path $env:LOCALAPPDATA 'Programs\Sudhamrtam'
# A running copy would lock its files.
Get-Process sudhamrtam_customer_app -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Milliseconds 500
if (Test-Path $target) { Remove-Item -Recurse -Force $target }
New-Item -ItemType Directory -Force $target | Out-Null
Copy-Item -Recurse -Force (Join-Path $build '*') $target

$exe = Join-Path $target 'sudhamrtam_customer_app.exe'
$shell = New-Object -ComObject WScript.Shell
$places = @(
  [Environment]::GetFolderPath('Desktop'),
  (Join-Path ([Environment]::GetFolderPath('Programs')) '')
)
foreach ($folder in $places) {
  $link = $shell.CreateShortcut((Join-Path $folder 'Sudhamrtam.lnk'))
  $link.TargetPath = $exe
  $link.WorkingDirectory = $target
  $link.IconLocation = "$exe,0"
  $link.Description = 'Sudhamrtam'
  $link.Save()
}
"Installed in $target, with Desktop and Start menu shortcuts."
