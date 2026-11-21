# One-time setup of the Windows build toolchain for super远程桌面 (SuperDesk).
# Versions are pinned to match RustDesk's CI (.github/workflows/flutter-build.yml).
# Everything goes under $env:SUPERDESK_HOME (default D:\superdesk) -- an ASCII path,
# because Flutter/ffmpeg builds break on paths with non-ASCII characters.
# Safe to re-run: finished steps are skipped.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$RUST_VERSION    = '1.75'
$LLVM_VERSION    = '15.0.6'
$FLUTTER_VERSION = '3.24.5'
$VCPKG_COMMIT    = '9e593bb18ea69cc5095e012465dcd675a822ed0d'

# vcpkg's WinHTTP downloader rejects "::1" in the proxy bypass list (error 0x57).
foreach ($v in 'no_proxy', 'NO_PROXY') {
    $cur = [Environment]::GetEnvironmentVariable($v, 'Process')
    if ($cur) { [Environment]::SetEnvironmentVariable($v, (($cur -split '[,;]' | Where-Object { $_ -and $_ -ne '::1' }) -join ','), 'Process') }
}

# Third-party Flutter mirrors (e.g. TUNA) lack artifacts of older releases (Dart SDK 404); Flutter's
# official China mirror is complete and fast. SUPERDESK_FLUTTER_MIRROR=off uses Google storage instead.
if ($env:SUPERDESK_FLUTTER_MIRROR -eq 'off') {
    Remove-Item Env:FLUTTER_STORAGE_BASE_URL, Env:PUB_HOSTED_URL -ErrorAction SilentlyContinue
} else {
    $env:FLUTTER_STORAGE_BASE_URL = 'https://storage.flutter-io.cn'
    $env:PUB_HOSTED_URL = 'https://pub.flutter-io.cn'
}

$RepoRoot = (Resolve-Path "$PSScriptRoot\..\..").Path
$Home_    = if ($env:SUPERDESK_HOME) { $env:SUPERDESK_HOME } else { 'D:\superdesk' }
$Tools    = Join-Path $Home_ 'tools'
New-Item -ItemType Directory -Force $Tools | Out-Null

function Step($name) { Write-Host "`n=== $name ===" -ForegroundColor Cyan }

# --- Rust ---------------------------------------------------------------
Step "Rust $RUST_VERSION"
rustup toolchain install $RUST_VERSION --profile minimal -c rustfmt
if ($LASTEXITCODE) { throw 'rustup failed' }

# --- LLVM (libclang for bindgen) ----------------------------------------
Step "LLVM $LLVM_VERSION"
$Llvm = Join-Path $Tools 'llvm'
if (-not (Test-Path "$Llvm\bin\libclang.dll")) {
    $exe = Join-Path $Tools "LLVM-$LLVM_VERSION-win64.exe"
    if (-not (Test-Path $exe)) {
        Invoke-WebRequest "https://github.com/llvm/llvm-project/releases/download/llvmorg-$LLVM_VERSION/LLVM-$LLVM_VERSION-win64.exe" -OutFile $exe
    }
    # NSIS: /D must be last and unquoted
    Start-Process -Wait -FilePath $exe -ArgumentList '/S', "/D=$Llvm"
    if (-not (Test-Path "$Llvm\bin\libclang.dll")) { throw 'LLVM install failed' }
}

# --- vcpkg --------------------------------------------------------------
Step "vcpkg @ $VCPKG_COMMIT"
$Vcpkg = Join-Path $Tools 'vcpkg'
if (-not (Test-Path "$Vcpkg\.git")) {
    git clone https://github.com/microsoft/vcpkg.git $Vcpkg
    if ($LASTEXITCODE) { throw 'vcpkg clone failed' }
}
git -C $Vcpkg fetch --quiet origin
git -C $Vcpkg checkout --quiet $VCPKG_COMMIT
if ($LASTEXITCODE) { throw 'vcpkg checkout failed' }
if (-not (Test-Path "$Vcpkg\vcpkg.exe")) {
    & "$Vcpkg\bootstrap-vcpkg.bat" -disableMetrics
    if ($LASTEXITCODE) { throw 'vcpkg bootstrap failed' }
}

# --- Flutter (pinned + RustDesk patch + RustDesk custom engine) -----------
Step "Flutter $FLUTTER_VERSION"
$Flutter = Join-Path $Tools "flutter-$FLUTTER_VERSION"
if (-not (Test-Path "$Flutter\bin\flutter.bat")) {
    git clone --branch $FLUTTER_VERSION --depth 1 https://github.com/flutter/flutter.git $Flutter
    if ($LASTEXITCODE) { throw 'flutter clone failed' }
}
$env:Path = "$Flutter\bin;$env:Path"
$Patch = Join-Path $RepoRoot '.github\patches\flutter_3.24.4_dropdown_menu_enableFilter.diff'
git -C $Flutter apply --check $Patch 2>$null
if ($LASTEXITCODE -eq 0) { git -C $Flutter apply $Patch; Write-Host 'dropdown patch applied' }
else { Write-Host 'dropdown patch already applied (or not applicable)' }

flutter config --no-analytics | Out-Null
flutter precache --windows
if ($LASTEXITCODE) { throw 'flutter precache failed' }

$EngineDir = "$Flutter\bin\cache\artifacts\engine\windows-x64-release"
$Marker = "$EngineDir\.rustdesk-engine"
if (-not (Test-Path $Marker)) {
    $zip = Join-Path $Tools 'windows-x64-release.zip'
    Invoke-WebRequest 'https://github.com/rustdesk/engine/releases/download/main/windows-x64-release.zip' -OutFile $zip
    $tmp = Join-Path $Tools 'engine-tmp'
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
    Expand-Archive $zip -DestinationPath $tmp
    Copy-Item -Recurse -Force "$tmp\*" $EngineDir
    Remove-Item -Recurse -Force $tmp
    New-Item -ItemType File $Marker | Out-Null
    Write-Host 'RustDesk custom engine installed'
}

Step 'Done'
Write-Host "LLVM:    $Llvm"
Write-Host "vcpkg:   $Vcpkg"
Write-Host "Flutter: $Flutter"
