# Build the super远程桌面 Windows clients (x64) natively.
# Prerequisites: setup-windows-toolchain.ps1 has run, and bridge files exist
#                (build-android.ps1 -BridgeOnly generates them).
#   .\build-windows.ps1                    # both flavors: full (IT) + helper (employees)
#   .\build-windows.ps1 -Flavor helper     # one flavor
#   .\build-windows.ps1 -SkipVcpkg         # skip the vcpkg dependency check (faster rebuilds)
# Output: dist\<AppName>-<version>-<build>-win-x64.exe (+ .json build info for publish.ps1)
#         single exe: run = portable, or click "Install" inside.
param(
    [ValidateSet('full', 'helper')]
    [string[]]$Flavor = @('full', 'helper'),
    [switch]$SkipVcpkg
)
. "$PSScriptRoot\common.ps1"

$Flutter = Join-Path $SdTools 'flutter-3.24.5'
$Llvm    = Join-Path $SdTools 'llvm'
$Vcpkg   = Join-Path $SdTools 'vcpkg'
foreach ($p in "$Flutter\bin\flutter.bat", "$Llvm\bin\libclang.dll", "$Vcpkg\vcpkg.exe") {
    if (-not (Test-Path $p)) { throw "Missing $p -- run setup-windows-toolchain.ps1 first." }
}
if (-not (Test-BridgeFiles)) { throw 'Bridge files missing -- run build-android.ps1 -BridgeOnly first.' }

$env:VCPKG_ROOT = $Vcpkg
$env:VCPKG_DEFAULT_HOST_TRIPLET = 'x64-windows-static'
$env:LIBCLANG_PATH = "$Llvm\bin"
$env:RUSTUP_TOOLCHAIN = '1.75'
$env:Path = "$Flutter\bin;$Llvm\bin;$env:Path"
if (-not $env:SUPERDESK_BUILD) { $env:SUPERDESK_BUILD = Get-Date -Format 'yyyyMMddHHmm' }
$version = Get-SuperdeskVersion
New-Item -ItemType Directory -Force $DistDir | Out-Null

foreach ($fl in $Flavor) {
    Step "Flavor: $fl  (build $env:SUPERDESK_BUILD)"
    $buildEnv = Get-SuperdeskBuildEnv $fl
    foreach ($kv in $buildEnv.GetEnumerator()) { Set-Item "Env:$($kv.Key)" $kv.Value }

    Sync-Source
    Set-Location $SdSrc
    # Per-flavor product name in the exe's version info (file description shown in Task Manager).
    $rc = Join-Path $SdSrc 'flutter\windows\runner\Runner.rc'
    $rcText = [IO.File]::ReadAllText($rc).Replace('"super远程桌面"', '"' + $buildEnv.SUPERDESK_DISPLAY_NAME + '"').
        Replace('"rustdesk.exe"', '"' + $buildEnv.SUPERDESK_APP_NAME + '.exe"')
    [IO.File]::WriteAllText($rc, $rcText, [Text.UTF8Encoding]::new($false))

    if (-not $SkipVcpkg) {
        Step 'vcpkg dependencies (x64-windows-static; first run builds ffmpeg etc.)'
        Invoke-Native "$Vcpkg\vcpkg.exe" install --triplet x64-windows-static "--x-install-root=$Vcpkg\installed"
        $SkipVcpkg = $true
    }

    Step 'cargo + flutter build'
    Invoke-Native python build.py --portable --flutter --skip-portable-pack --hwcodec --vram
    $Release = Join-Path $SdSrc 'flutter\build\windows\x64\runner\Release'

    # The Windows installer, service and shortcuts all use "<APP_NAME>.exe" (only upgrades rename
    # rustdesk.exe), so ship the main binary under that name. Drop the other flavor's exe first.
    $appExe = "$($buildEnv.SUPERDESK_APP_NAME).exe"
    Get-ChildItem $Release -Filter 'SuperDesk*.exe' | Remove-Item -Force
    Move-Item (Join-Path $Release 'rustdesk.exe') (Join-Path $Release $appExe) -Force

    Step 'Extras: virtual display driver (same as official package)'
    if (-not (Test-Path "$Release\usbmmidd_v2")) {
        $zip = Join-Path $SdTools 'usbmmidd_v2.zip'
        if (-not (Test-Path $zip)) {
            Invoke-WebRequest 'https://github.com/rustdesk-org/rdev/releases/download/usbmmidd_v2/usbmmidd_v2.zip' -OutFile $zip
        }
        $tmp = Join-Path $SdHome 'usbmmidd-tmp'
        Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
        Expand-Archive $zip -DestinationPath $tmp
        Remove-Item -Recurse -Force "$tmp\usbmmidd_v2\Win32"
        Remove-Item -Force "$tmp\usbmmidd_v2\deviceinstaller64.exe", "$tmp\usbmmidd_v2\deviceinstaller.exe", "$tmp\usbmmidd_v2\usbmmidd.bat"
        Move-Item "$tmp\usbmmidd_v2" $Release
        Remove-Item -Recurse -Force $tmp
    }

    Step 'Extras: 防窥 cover window (WindowInjection.dll, patched)'
    $patch = Join-Path $SdSrc 'superdesk\patches\topmost-window.patch'
    $cover = Join-Path $SdTools "WindowInjection-$((Get-FileHash $patch).Hash.Substring(0, 12)).dll"
    if (-not (Test-Path $cover)) {
        $twSrc = Join-Path $SdHome 'third_party\RustDeskTempTopMostWindow'
        if (-not (Test-Path $twSrc)) {
            Invoke-Native git clone -q https://github.com/rustdesk-org/RustDeskTempTopMostWindow $twSrc
        }
        Invoke-Native git -C $twSrc checkout -q -f ecd8d6a139eee76845ea66423fb739af450fda90
        Invoke-Native git -C $twSrc apply $patch
        $msbuild = & "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * `
            -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' | Select-Object -First 1
        Invoke-Native $msbuild "$twSrc\WindowInjection\WindowInjection.vcxproj" /nologo /v:minimal `
            /p:Configuration=Release /p:Platform=x64 /p:PlatformToolset=v143 /p:TargetVersion=Windows10
        Copy-Item "$twSrc\WindowInjection\x64\Release\WindowInjection.dll" $cover
    }
    Copy-Item $cover (Join-Path $Release 'WindowInjection.dll') -Force

    Step 'Pack single-file exe'
    Push-Location (Join-Path $SdSrc 'libs\portable')
    try {
        Invoke-Native python -m pip install -q -r requirements.txt
        Invoke-Native python generate.py -f $Release -o . -e "$Release\$appExe"
    } finally { Pop-Location }

    $name = "$($buildEnv.SUPERDESK_APP_NAME)-$version-$env:SUPERDESK_BUILD-win-x64.exe"
    $out = Join-Path $DistDir $name
    Copy-Item (Join-Path $SdSrc 'target\release\rustdesk-portable-packer.exe') $out -Force
    @{ platform = 'windows'; flavor = $fl; version = $version; build = $env:SUPERDESK_BUILD
       file = $name; display_name = $buildEnv.SUPERDESK_DISPLAY_NAME } |
        ConvertTo-Json | Set-Content "$out.json" -Encoding utf8
    Write-Host "OUTPUT: $out" -ForegroundColor Green
}
