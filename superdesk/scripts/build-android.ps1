# Build the super远程桌面 Android APK (and the flutter_rust_bridge files) in Docker.
#   .\build-android.ps1                         # arm64-v8a APK (most phones)
#   .\build-android.ps1 -Abi arm64-v8a,armeabi-v7a
#   .\build-android.ps1 -BridgeOnly             # only (re)generate bridge files (needed by Windows build too)
#   .\build-android.ps1 -Bridge                 # force bridge regeneration, then build APK
# Output: dist\SuperDesk-<version>-<abi>.apk
param(
    [ValidateSet('arm64-v8a', 'armeabi-v7a', 'x86_64')]
    [string[]]$Abi = @('arm64-v8a'),
    [switch]$Bridge,
    [switch]$BridgeOnly
)
. "$PSScriptRoot\common.ps1"

$Image = 'superdesk-builder:1.5.3'
$SdSrcAndroid = Join-Path $SdHome 'src-android'
$Triplets = @{ 'arm64-v8a' = 'arm64-android'; 'armeabi-v7a' = 'arm-neon-android'; 'x86_64' = 'x64-android' }

# --- builder image ---------------------------------------------------------
Step "Docker image $Image"
$ctx = Join-Path $SdHome 'docker-ctx'
Remove-Item -Recurse -Force $ctx -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force "$ctx\vcpkg-manifest\res" | Out-Null
Copy-Item "$RepoRoot\superdesk\docker\builder.Dockerfile", "$RepoRoot\superdesk\docker\build-in-container.sh" $ctx
Copy-Item "$RepoRoot\.github\patches\flutter_3.24.4_dropdown_menu_enableFilter.diff" $ctx
Copy-Item "$RepoRoot\vcpkg.json" "$ctx\vcpkg-manifest\"
Copy-Item -Recurse "$RepoRoot\res\vcpkg", "$RepoRoot\res\vcpkg-triplets" "$ctx\vcpkg-manifest\res\"
# Always build all requested + previously used triplets so the cached layer keeps them.
$allTriplets = @(@($Abi | ForEach-Object { $Triplets[$_] }) + @('arm64-android') | Sort-Object -Unique)
# Docker Desktop injects the host proxy into builds/containers; it proved flaky for long downloads
# while direct access works, so blank it out. Set SUPERDESK_DOCKER_KEEP_PROXY=1 to keep it.
$noProxyBuild = @(); $noProxyRun = @()
if (-not $env:SUPERDESK_DOCKER_KEEP_PROXY) {
    foreach ($v in 'http_proxy', 'https_proxy', 'HTTP_PROXY', 'HTTPS_PROXY') {
        $noProxyBuild += @('--build-arg', "$v="); $noProxyRun += @('-e', "$v=")
    }
}
Invoke-Native docker build @noProxyBuild -f "$ctx\builder.Dockerfile" -t $Image --build-arg "VCPKG_TRIPLETS=$($allTriplets -join ' ')" $ctx

Sync-Source $SdSrcAndroid
New-Item -ItemType Directory -Force $SdOut, $DistDir | Out-Null
$mirrorRun = @()
if ($env:FLUTTER_STORAGE_BASE_URL) { $mirrorRun += @('-e', "FLUTTER_STORAGE_BASE_URL=$env:FLUTTER_STORAGE_BASE_URL") }
if ($env:PUB_HOSTED_URL) { $mirrorRun += @('-e', "PUB_HOSTED_URL=$env:PUB_HOSTED_URL") }
$common = @('run', '--rm') + $noProxyRun + $mirrorRun + @('-v', "${SdSrcAndroid}:/src:ro", '-v', 'superdesk-work:/work',
            '-v', 'superdesk-cargo-registry:/opt/cargo/registry', '-v', 'superdesk-cargo-git:/opt/cargo/git',
            '-v', 'superdesk-gradle:/root/.gradle', '-v', 'superdesk-pub:/root/.pub-cache',
            '-v', "${SdOut}:/out")

# --- bridge ----------------------------------------------------------------
if ($Bridge -or $BridgeOnly -or -not (Test-BridgeFiles)) {
    Step 'flutter_rust_bridge codegen'
    Invoke-Native docker @common $Image bridge
    foreach ($f in $BridgeFiles) {
        $dst = Join-Path $RepoRoot $f
        Copy-Item (Join-Path "$SdOut\bridge" $f) $dst -Force
    }
    Sync-Source $SdSrcAndroid
    Write-Host 'bridge files written into the repo (git-ignored)'
}
if ($BridgeOnly) { return }

# --- signing key (keep secrets\android forever: updates need the same key) --
if (-not (Test-Path "$SecretsDir\android\key.properties")) {
    Step 'Generate Android signing key'
    Invoke-Native docker run --rm -v "${SecretsDir}:/secrets" $Image keygen
}

# --- APK -------------------------------------------------------------------
if (-not $env:SUPERDESK_BUILD) { $env:SUPERDESK_BUILD = Get-Date -Format 'yyyyMMddHHmm' }
$envFile = Join-Path $env:TEMP "superdesk-build-$PID.env"
try {
    $lines = (Get-SuperdeskBuildEnv 'full').GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }
    [IO.File]::WriteAllLines($envFile, [string[]]$lines, [Text.UTF8Encoding]::new($false))
    foreach ($a in $Abi) {
        Step "Android APK $a (build $env:SUPERDESK_BUILD)"
        Invoke-Native docker @common --env-file $envFile -v "${SecretsDir}:/secrets:ro" $Image android $a
        Get-ChildItem "$SdOut\*.apk", "$SdOut\*.apk.json" | ForEach-Object {
            Copy-Item $_.FullName $DistDir -Force
            if ($_.Extension -eq '.apk') { Write-Host "OUTPUT: $DistDir\$($_.Name)" -ForegroundColor Green }
        }
    }
} finally {
    Remove-Item $envFile -ErrorAction SilentlyContinue
}
