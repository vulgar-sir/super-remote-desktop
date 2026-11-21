# Generate flutter_rust_bridge files natively on Windows (alternative to build-android.ps1 -BridgeOnly).
# Same pinned versions as RustDesk CI (bridge.yml): Rust 1.75, FRB codegen 1.80.1, cargo-expand 1.0.95,
# Flutter 3.22.3 (with extended_text pinned to 13.0.0 for resolution, as CI does).
# Tools go to $SUPERDESK_HOME\tools; outputs are copied into the repo (git-ignored files).
. "$PSScriptRoot\common.ps1"

$Fl322   = Join-Path $SdTools 'flutter-3.22.3'
$CargoBin = Join-Path $SdTools 'cargo-tools'
$Llvm    = Join-Path $SdTools 'llvm'
$env:RUSTUP_TOOLCHAIN = '1.75'
$env:LIBCLANG_PATH = "$Llvm\bin"

Step 'codegen tools'
if (-not (Test-Path "$CargoBin\bin\cargo-expand.exe")) {
    Invoke-Native cargo install cargo-expand --version 1.0.95 --locked --root $CargoBin
}
if (-not (Test-Path "$CargoBin\bin\flutter_rust_bridge_codegen.exe")) {
    Invoke-Native cargo install flutter_rust_bridge_codegen --version 1.80.1 --features uuid --locked --root $CargoBin
}

Step 'Flutter 3.22.3'
if (-not (Test-Path "$Fl322\bin\flutter.bat")) {
    Invoke-Native git clone --branch 3.22.3 --depth 1 https://github.com/flutter/flutter.git $Fl322
}
$env:Path = "$CargoBin\bin;$Fl322\bin;$Llvm\bin;$env:Path"
Invoke-Native flutter --version

Sync-Source
Set-Location $SdSrc
Step 'pub get (extended_text pinned to 13.0.0 like CI)'
$pub = Join-Path $SdSrc 'flutter\pubspec.yaml'
[IO.File]::WriteAllText($pub, [IO.File]::ReadAllText($pub).Replace('extended_text: 14.0.0', 'extended_text: 13.0.0'))
Push-Location flutter; try { Invoke-Native flutter pub get } finally { Pop-Location }

Step 'flutter_rust_bridge_codegen'
Invoke-Native flutter_rust_bridge_codegen --rust-input ./src/flutter_ffi.rs --dart-output ./flutter/lib/generated_bridge.dart `
    --c-output ./flutter/macos/Runner/bridge_generated.h --llvm-path $Llvm
Copy-Item .\flutter\macos\Runner\bridge_generated.h .\flutter\ios\Runner\bridge_generated.h -Force

foreach ($f in $BridgeFiles) {
    $src = Join-Path $SdSrc $f
    if (-not (Test-Path $src)) { throw "codegen did not produce $f" }
    Copy-Item $src (Join-Path $RepoRoot $f) -Force
}
# Restore pubspec.yaml / pubspec.lock in the mirror (next Sync-Source would anyway).
Sync-Source
Write-Host 'BRIDGE OK (files copied into the repo)' -ForegroundColor Green
