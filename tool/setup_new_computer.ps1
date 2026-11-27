<#
Sudhamrtam: move development to another Windows computer.
Guide: docs/NEW_COMPUTER.md. Sudhamrtam only (Ayyappa Diksha is a separate project).

  Old PC, copy secrets to a USB drive:
    powershell -ExecutionPolicy Bypass -File setup_new_computer.ps1 -ExportTo E:\
  New PC, check, install what is missing, clone the repos, put the secrets in place:
    powershell -ExecutionPolicy Bypass -File E:\sudhamrtam-move\setup_new_computer.ps1 -ImportFrom E:\sudhamrtam-move
  Any PC, only check (changes nothing):
    powershell -ExecutionPolicy Bypass -File setup_new_computer.ps1 -CheckOnly

The script never prints the contents of a secret file and never overwrites a file that exists.
#>
param(
    [string]$Root = 'D:\Sudhamrtam',
    [string]$ExportTo,
    [string]$ImportFrom,
    [switch]$CheckOnly,
    [switch]$Yes
)

$ErrorActionPreference = 'Stop'

# Flutter version used on the main PC (27 Nov 2026). Update when Flutter is upgraded there.
$FlutterVersion = '3.47.9'
$FlutterDir = 'C:\src\flutter'

$Repos = [ordered]@{
    'sudhamrtam_backend'         = 'https://github.com/sudhamrtam-ux/sudhamrtam_backend.git'
    'sudhamrtam_customer_app'    = 'https://github.com/sudhamrtam-ux/sudhamrtam-customer-app.git'
    'sudhamrtam_staff_app'       = 'https://github.com/sudhamrtam-ux/sudhamrtam_staff_app.git'
    'sudhamrtam_procurement_app' = 'https://github.com/sudhamrtam-ux/sudhamrtam-procurement-app.git'
    'sudhamrtam_counter_app'     = 'https://github.com/sudhamrtam-ux/sudhamrtam-counter-app.git'
}
$FlutterApps = @('sudhamrtam_customer_app', 'sudhamrtam_staff_app', 'sudhamrtam_procurement_app', 'sudhamrtam_counter_app')

# Files that are not in git, relative to $Root. "need" = builds fail or break without it.
$Secrets = @(
    @{ Path = 'signing\sudhamrtam-release.jks';                          Need = 'release signing key for all 4 apps (losing it = no updates on Play)' }
    @{ Path = 'signing\KEEP-SECRET-password.txt';                        Need = 'password of the signing key' }
    @{ Path = 'sudhamrtam_customer_app\android\key.properties';          Need = 'customer release signing' }
    @{ Path = 'sudhamrtam_staff_app\android\key.properties';             Need = 'staff release signing' }
    @{ Path = 'sudhamrtam_procurement_app\android\key.properties';       Need = 'procurement release signing' }
    @{ Path = 'sudhamrtam_counter_app\android\key.properties';           Need = 'counter release signing' }
    @{ Path = 'sudhamrtam_customer_app\android\app\google-services.json'; Need = 'customer Android build (Firebase)' }
    @{ Path = 'sudhamrtam_staff_app\android\app\google-services.json';   Need = 'staff Android build (Firebase)' }
    @{ Path = 'sudhamrtam_customer_app\android\maps-key.txt';            Need = 'map in the customer Android app' }
    @{ Path = 'sudhamrtam_customer_app\web\maps-key.txt';                Need = 'map on the website build' }
    @{ Path = 'tools\nuget\nuget.exe';                                   Need = 'Windows desktop builds' }
)

# Programs installed with winget. Test = how to tell it is there.
$Programs = @(
    @{ Name = 'Git';                Id = 'Git.Git';                    Test = { Test-Cmd 'git' } }
    @{ Name = 'Visual Studio Code'; Id = 'Microsoft.VisualStudioCode'; Test = { Test-Cmd 'code' } }
    @{ Name = 'Node.js (LTS)';      Id = 'OpenJS.NodeJS.LTS';          Test = { Test-Cmd 'node' } }
    @{ Name = 'Python 3';           Id = 'Python.Python.3.13';         Test = { Test-Python } }
    @{ Name = 'Android Studio';     Id = 'Google.AndroidStudio';       Test = { Test-Path "$env:ProgramFiles\Android\Android Studio\bin\studio64.exe" } }
)
$VsCodeExtensions = @('anthropic.claude-code', 'dart-code.flutter')

$script:Missing = New-Object System.Collections.ArrayList

function Say([string]$Text, [string]$Color = 'Gray') { Write-Host $Text -ForegroundColor $Color }
function Ok([string]$Text) { Write-Host "  [ok]      $Text" -ForegroundColor Green }
function Miss([string]$Text) { Write-Host "  [missing] $Text" -ForegroundColor Yellow; [void]$script:Missing.Add($Text) }
function Info([string]$Text) { Write-Host "  [note]    $Text" -ForegroundColor Cyan }

function Test-Cmd([string]$Name) { return [bool](Get-Command $Name -ErrorAction SilentlyContinue) }
function Test-Python {
    # The Microsoft Store "python" stub exists on fresh Windows but is not Python.
    $cmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $cmd) { return $false }
    return ($cmd.Source -notlike '*WindowsApps*')
}

function Update-SessionPath {
    $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = "$machine;$user"
    $pub = [Environment]::GetEnvironmentVariable('PUB_CACHE', 'User')
    if ($pub) { $env:PUB_CACHE = $pub }
}

function Confirm-Step([string]$Question) {
    if ($Yes) { return $true }
    $answer = Read-Host "$Question (y/n)"
    return ($answer -match '^(y|yes)$')
}

function Add-UserPath([string]$Dir) {
    $user = [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not $user) { $user = '' }
    $parts = $user.Split(';') | Where-Object { $_ -ne '' }
    if ($parts -notcontains $Dir) {
        [Environment]::SetEnvironmentVariable('Path', (($parts + $Dir) -join ';'), 'User')
    }
    Update-SessionPath
}

# ---------------------------------------------------------------- export (old PC)
if ($ExportTo) {
    $dest = Join-Path $ExportTo 'sudhamrtam-move'
    Say "Copying Sudhamrtam secrets and notes to $dest" 'White'
    New-Item -ItemType Directory -Force $dest | Out-Null
    foreach ($s in $Secrets) {
        $from = Join-Path $Root $s.Path
        if (Test-Path $from) {
            $to = Join-Path (Join-Path $dest 'files') $s.Path
            New-Item -ItemType Directory -Force (Split-Path $to) | Out-Null
            Copy-Item $from $to -Force
            Ok $s.Path
        } else {
            Miss "$($s.Path) is not on this PC either"
        }
    }
    # Claude Code's notes for the Sudhamrtam folders (memory only, not the chat history).
    $projects = Join-Path $env:USERPROFILE '.claude\projects'
    if (Test-Path $projects) {
        Get-ChildItem $projects -Directory | Where-Object { $_.Name -match '^[dD]--Sudhamrtam-' -and (Test-Path (Join-Path $_.FullName 'memory')) } | ForEach-Object {
            $to = Join-Path $dest "claude-memory\$($_.Name)\memory"
            New-Item -ItemType Directory -Force $to | Out-Null
            Copy-Item (Join-Path $_.FullName 'memory\*') $to -Recurse -Force
            Ok "Claude notes: $($_.Name)"
        }
    }
    Copy-Item $PSCommandPath (Join-Path $dest 'setup_new_computer.ps1') -Force
    $guide = Join-Path (Split-Path $PSScriptRoot) 'docs\NEW_COMPUTER.md'
    if (Test-Path $guide) { Copy-Item $guide (Join-Path $dest 'NEW_COMPUTER.md') -Force }
    Say ''
    Say "Done. $dest now holds the signing key and passwords:" 'White'
    Say '  keep the USB drive with you, and delete the folder from it once the new PC works.' 'Yellow'
    exit 0
}

# ---------------------------------------------------------------- 1. drive and programs
Say ''
Say 'Sudhamrtam: checking this computer' 'White'
Say '1. Drive and programs' 'White'

$drive = Split-Path $Root -Qualifier
if (-not (Test-Path "$drive\")) {
    Say "  Drive $drive does not exist. Run again with -Root <folder>, for example -Root C:\Sudhamrtam." 'Red'
    Say '  (Claude Code keeps its notes per folder path, so the same path as the old PC is best.)' 'Red'
    exit 1
}
Ok "drive $drive"

if (-not (Test-Cmd 'winget')) {
    Miss 'winget (App Installer from the Microsoft Store): needed to install programs'
}

$toInstall = @()
foreach ($p in $Programs) {
    if (& $p.Test) { Ok $p.Name } else { Miss $p.Name; $toInstall += $p }
}

if ($toInstall.Count -gt 0 -and -not $CheckOnly -and (Test-Cmd 'winget')) {
    $names = ($toInstall | ForEach-Object { $_.Name }) -join ', '
    if (Confirm-Step "Install $names with winget?") {
        foreach ($p in $toInstall) {
            Say "  installing $($p.Name)..." 'White'
            winget install --id $p.Id -e --accept-package-agreements --accept-source-agreements
            if ($LASTEXITCODE -ne 0) { Say "  winget could not install $($p.Name) (code $LASTEXITCODE)." 'Red' }
        }
        Update-SessionPath
    }
}

# Flutter
$flutterOk = Test-Cmd 'flutter'
if (-not $flutterOk -and (Test-Path "$FlutterDir\bin\flutter.bat")) {
    Add-UserPath "$FlutterDir\bin"; $flutterOk = $true
}
if (-not $flutterOk) {
    Miss "Flutter $FlutterVersion"
    if (-not $CheckOnly -and (Test-Cmd 'git') -and (Confirm-Step "Download Flutter $FlutterVersion into $FlutterDir?")) {
        New-Item -ItemType Directory -Force (Split-Path $FlutterDir) | Out-Null
        git clone --branch stable https://github.com/flutter/flutter.git $FlutterDir
        git -C $FlutterDir checkout $FlutterVersion
        Add-UserPath "$FlutterDir\bin"
        $flutterOk = Test-Cmd 'flutter'
    }
}
if ($flutterOk) {
    $line = (flutter --version 2>$null | Select-Object -First 1)
    if ($line -match "Flutter $([regex]::Escape($FlutterVersion)) ") { Ok "Flutter $FlutterVersion" }
    else { Info "Flutter is a different version than the main PC ($FlutterVersion): $line" }
}

# PUB_CACHE on the same drive as the projects (Kotlin fails across drives)
$wantPub = "$drive\PubCache"
$pub = [Environment]::GetEnvironmentVariable('PUB_CACHE', 'User')
if ($pub -and ((Split-Path $pub -Qualifier) -eq $drive)) { Ok "PUB_CACHE = $pub" }
else {
    Miss "PUB_CACHE on drive $drive"
    if (-not $CheckOnly -and (Confirm-Step "Set PUB_CACHE to $wantPub?")) {
        New-Item -ItemType Directory -Force $wantPub | Out-Null
        [Environment]::SetEnvironmentVariable('PUB_CACHE', $wantPub, 'User')
        $env:PUB_CACHE = $wantPub
    }
}

# Android SDK (Android Studio downloads it on its first start)
$sdk = $env:ANDROID_HOME
if (-not $sdk) { $sdk = [Environment]::GetEnvironmentVariable('ANDROID_HOME', 'User') }
if (-not $sdk) { $sdk = "$env:LOCALAPPDATA\Android\Sdk" }
if (Test-Path "$sdk\platform-tools\adb.exe") { Ok "Android SDK ($sdk)" }
else { Miss 'Android SDK: open Android Studio once and finish its setup wizard, then run this again' }

# Visual Studio C++ (only for Windows desktop builds)
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vsCpp = $null
if (Test-Path $vswhere) { $vsCpp = & $vswhere -latest -requires Microsoft.VisualStudio.Workload.NativeDesktop -property displayName }
if ($vsCpp) { Ok "$vsCpp with C++ (Windows builds)" }
else { Info 'Visual Studio with "Desktop development with C++" is not installed: only needed for Windows app builds (visualstudio.microsoft.com, Community edition).' }

# VS Code extensions
if (Test-Cmd 'code') {
    $have = code --list-extensions
    foreach ($e in $VsCodeExtensions) {
        if ($have -contains $e) { Ok "VS Code extension $e" }
        else {
            Miss "VS Code extension $e"
            if (-not $CheckOnly) { code --install-extension $e | Out-Null }
        }
    }
}

# ---------------------------------------------------------------- 2. code
Say '2. Code (GitHub)' 'White'
New-Item -ItemType Directory -Force $Root | Out-Null
foreach ($name in $Repos.Keys) {
    $dir = Join-Path $Root $name
    if (Test-Path "$dir\.git") {
        $dirty = git -C $dir status --porcelain
        if ($dirty) { Ok "$name (has local changes)" } else { Ok $name }
    } elseif (Test-Path $dir) {
        Say "  [problem] $dir exists but is not a git folder: move it away, then run again." 'Red'
        [void]$script:Missing.Add("$name (folder in the way)")
    } else {
        Miss $name
        if (-not $CheckOnly -and (Test-Cmd 'git')) {
            Say "  cloning $name (a GitHub sign-in window may open)..." 'White'
            git clone $Repos[$name] $dir
        }
    }
}

# ---------------------------------------------------------------- 3. secrets
Say '3. Files that are not in git' 'White'
foreach ($s in $Secrets) {
    $target = Join-Path $Root $s.Path
    if (Test-Path $target) { Ok $s.Path; continue }
    $copied = $false
    if ($ImportFrom -and -not $CheckOnly) {
        $from = Join-Path (Join-Path $ImportFrom 'files') $s.Path
        # Into a repo folder only once that repo is cloned.
        $top = $s.Path.Split('\')[0]
        $topReady = (-not $Repos.Contains($top)) -or (Test-Path (Join-Path $Root "$top\.git"))
        if ((Test-Path $from) -and $topReady) {
            New-Item -ItemType Directory -Force (Split-Path $target) | Out-Null
            Copy-Item $from $target
            Ok "$($s.Path) (copied from the USB)"
            $copied = $true
        }
    }
    if (-not $copied) { Miss "$($s.Path): $($s.Need)" }
}

if ($ImportFrom -and -not $CheckOnly -and (Test-Path (Join-Path $ImportFrom 'claude-memory'))) {
    $projects = Join-Path $env:USERPROFILE '.claude\projects'
    Get-ChildItem (Join-Path $ImportFrom 'claude-memory') -Directory | ForEach-Object {
        $to = Join-Path $projects "$($_.Name)\memory"
        if (Test-Path $to) { Ok "Claude notes $($_.Name) (already here, left as is)" }
        else {
            New-Item -ItemType Directory -Force $to | Out-Null
            Copy-Item (Join-Path $_.FullName 'memory\*') $to -Recurse
            Ok "Claude notes $($_.Name) (copied)"
        }
    }
}

# ---------------------------------------------------------------- 4. packages
Say '4. Packages' 'White'
$backend = Join-Path $Root 'sudhamrtam_backend'
if (Test-Path "$backend\package.json") {
    if (Test-Path "$backend\node_modules") { Ok 'backend packages' }
    else {
        Miss 'backend packages (npm ci)'
        if (-not $CheckOnly -and (Test-Cmd 'npm')) { Push-Location $backend; npm ci; Pop-Location }
    }
}
foreach ($app in $FlutterApps) {
    $dir = Join-Path $Root $app
    if (-not (Test-Path "$dir\pubspec.yaml")) { continue }
    if (Test-Path "$dir\.dart_tool\package_config.json") { Ok "$app packages" }
    else {
        Miss "$app packages (flutter pub get)"
        if (-not $CheckOnly -and (Test-Cmd 'flutter')) { Push-Location $dir; flutter pub get; Pop-Location }
    }
}

# ---------------------------------------------------------------- summary
Say ''
if ($script:Missing.Count -eq 0) {
    Say 'Everything is in place.' 'Green'
} elseif ($CheckOnly) {
    Say "$($script:Missing.Count) item(s) missing (listed above in yellow). Nothing was changed (-CheckOnly)." 'Yellow'
} else {
    Say 'Done. Run the script once more with -CheckOnly: whatever is still yellow needs your hands' 'Yellow'
    Say '(see docs/NEW_COMPUTER.md). Open a NEW terminal so the new PATH and PUB_CACHE apply.' 'Yellow'
}
if ($flutterOk -and -not $CheckOnly) {
    Say ''
    Say 'flutter doctor:' 'White'
    flutter doctor
    Say 'If it lists Android licenses, run: flutter doctor --android-licenses' 'Gray'
}
