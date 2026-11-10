<#
.SYNOPSIS
    Cross-compiles the UAM Rust FFI crate (uam_ffi) for Android ABIs and packs
    the resulting shared library into the Flutter Android jniLibs directory.

.DESCRIPTION
    A dedicated Android build entry point. It does NOT touch or reuse the
    Windows desktop build (scripts/build/build_rust.ps1).

    The script:
      * resolves the Android NDK from environment variables or the standard SDK
        location (no machine-specific path is hard-coded),
      * validates that the requested Rust targets are installed,
      * configures the NDK clang/linker/ar for each target,
      * builds release or debug uam_ffi for the requested ABI(s),
      * copies libuam_ffi.so into
        app/flutter/android/app/src/main/jniLibs/<abi>/,
      * verifies exported symbols when the NDK's llvm-nm is available.

    Host portable: works on Windows, Linux, and macOS PowerShell.
    Run `Get-Help ./build_android_rust.ps1 -Detailed` for setup notes.

.PARAMETER Abi
    Target Android ABI. `all` builds every supported ABI.

.PARAMETER Profile
    Cargo build profile: `debug` or `release`.

.PARAMETER Api
    Android API level used to select the NDK clang wrapper. Defaults to 24,
    matching the Flutter minSdkVersion.

.PARAMETER NdkPath
    Explicit Android NDK path. Overrides environment-variable discovery.

.PARAMETER Toolchain
    Rustup host toolchain used to build the cross-compilation host artifacts
    (proc-macros and build scripts). On Windows this defaults to
    `stable-x86_64-pc-windows-gnu`, matching `build_rust.ps1`, because the
    self-contained GNU linker is used instead of MSVC. Leave empty on
    Linux/macOS to use the default toolchain.

.EXAMPLE
    ./build_android_rust.ps1 -Abi arm64-v8a -Profile release

.EXAMPLE
    ./build_android_rust.ps1 -Abi all -Profile debug

.EXAMPLE
    ./build_android_rust.ps1 -Abi arm64-v8a -Toolchain stable-x86_64-pc-windows-msvc
#>
param(
    [ValidateSet('arm64-v8a', 'armeabi-v7a', 'x86_64', 'all')]
    [string] $Abi = 'arm64-v8a',

    [ValidateSet('debug', 'release')]
    [string] $Profile = 'debug',

    [int] $Api = 24,

    [string] $NdkPath,

    [string] $Toolchain = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$cratesDir = Join-Path $repoRoot 'crates'
$jniLibsRoot = Join-Path $repoRoot 'app/flutter/android/app/src/main/jniLibs'
$libraryFileName = 'libuam_ffi.so'

$isWindowsHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::Windows)
$isMacHost = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
    [System.Runtime.InteropServices.OSPlatform]::OSX)
$hostPrebuilt = if ($isWindowsHost) { 'windows-x86_64' } elseif ($isMacHost) { 'darwin-x86_64' } else { 'linux-x86_64' }
# The NDK ships the clang wrappers as `.cmd` scripts on Windows, but the LLVM
# binutils (llvm-nm, llvm-ar, llvm-ranlib) as `.exe` binaries.
$clangExeSuffix = if ($isWindowsHost) { '.cmd' } else { '' }
$binExeSuffix = if ($isWindowsHost) { '.exe' } else { '' }

# Windows hosts use the self-contained GNU toolchain (mirrors build_rust.ps1):
# the host has no MSVC linker, and the WinLibs gcc path contains spaces.
if (-not $Toolchain -and $isWindowsHost) { $Toolchain = 'stable-x86_64-pc-windows-gnu' }
if ($Toolchain) {
    $env:RUSTUP_TOOLCHAIN = $Toolchain
    Write-Output "[android] Rust host toolchain: $Toolchain"
    if ($Toolchain -like '*windows-gnu') {
        $env:CARGO_TARGET_X86_64_PC_WINDOWS_GNU_LINKER = 'rust-lld'
        $env:CARGO_TARGET_X86_64_PC_WINDOWS_GNU_RUSTFLAGS = '-C link-self-contained=yes'
    }
}

# ABI -> (Rust target triple, NDK clang wrapper prefix).
$abiMap = @{
    'arm64-v8a'   = @{ Target = 'aarch64-linux-android';   ClangPrefix = 'aarch64-linux-android' }
    'armeabi-v7a' = @{ Target = 'armv7-linux-androideabi'; ClangPrefix = 'armv7a-linux-androideabi' }
    'x86_64'      = @{ Target = 'x86_64-linux-android';    ClangPrefix = 'x86_64-linux-android' }
}

function Get-NdkPrebuiltBin {
    param([string] $NdkRoot)
    return (Join-Path $NdkRoot "toolchains/llvm/prebuilt/$hostPrebuilt/bin")
}

function Test-Ndk {
    param([string] $Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    if (-not (Test-Path (Join-Path $Path 'source.properties'))) { return $false }
    return (Test-Path (Get-NdkPrebuiltBin -NdkRoot $Path))
}

function Resolve-NdkPath {
    param([string] $Explicit)

    $candidates = [System.Collections.Generic.List[string]]::new()
    if ($Explicit) { $candidates.Add($Explicit) }
    foreach ($name in @('ANDROID_NDK_HOME', 'ANDROID_NDK_ROOT', 'NDK_HOME')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { $candidates.Add($value) }
    }

    $sdkRoots = @()
    foreach ($name in @('ANDROID_SDK_ROOT', 'ANDROID_HOME')) {
        $value = [Environment]::GetEnvironmentVariable($name)
        if ($value) { $sdkRoots += $value }
    }
    $localAppData = [Environment]::GetEnvironmentVariable('LOCALAPPDATA')
    if ($localAppData) { $sdkRoots += (Join-Path $localAppData 'Android/Sdk') }
    if ($env:HOME) { $sdkRoots += (Join-Path $env:HOME 'Android/Sdk') }

    foreach ($sdk in $sdkRoots) {
        $ndkRoot = Join-Path $sdk 'ndk'
        if (-not (Test-Path $ndkRoot)) { continue }
        $versionDirs = Get-ChildItem -Path $ndkRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending
        foreach ($dir in $versionDirs) { $candidates.Add($dir.FullName) }
    }

    foreach ($candidate in $candidates) {
        if (Test-Ndk -Path $candidate) { return (Resolve-Path $candidate).Path }
    }

    $checked = ($candidates | ForEach-Object { "  - $_" }) -join "`n"
    throw @"
Android NDK not found or incomplete.

Checked:
$checked

Install the NDK (matching Flutter's expected version 28.2.13676358) and/or set
ANDROID_NDK_HOME, then retry. Example:

  sdkmanager --install "ndk;28.2.13676358"

See docs/ANDROID_SETUP.md.
"@
}

function Assert-RustTarget {
    param([string] $Target)
    $installed = @(rustup target list --installed 2>&1 | ForEach-Object { $_.ToString().Trim() })
    if ($installed -notcontains $Target) {
        throw @"
Rust target '$Target' is not installed.

Install it with:

  rustup target add $Target

See docs/ANDROID_SETUP.md.
"@
    }
}

function Invoke-AndroidBuild {
    param([string] $AbiName, [string] $NdkRoot, [int] $ApiLevel)

    $mapping = $abiMap[$AbiName]
    $target = $mapping.Target
    $clangFile = $mapping.ClangPrefix + $ApiLevel + '-clang' + $clangExeSuffix
    $prebuiltBin = Get-NdkPrebuiltBin -NdkRoot $NdkRoot
    $clangPath = Join-Path $prebuiltBin $clangFile

    if (-not (Test-Path $clangPath)) {
        throw "NDK clang wrapper not found: $clangPath`nVerify the NDK install or pass -Api with a supported level."
    }

    Assert-RustTarget -Target $target

    $envKey = 'CARGO_TARGET_' + ($target.ToUpper() -replace '-', '_') + '_LINKER'
    Set-Item -Path ("Env:" + $envKey) -Value $clangPath

    # cc-rs style variables (no C dependencies today, but keep future ones working).
    $toolSuffix = ($target -replace '-', '_')
    Set-Item -Path ("Env:CC_$toolSuffix") -Value $clangPath
    $llvmAr = Join-Path $prebuiltBin ('llvm-ar' + $binExeSuffix)
    if (Test-Path $llvmAr) {
        Set-Item -Path ("Env:AR_$toolSuffix") -Value $llvmAr
        Set-Item -Path ("Env:RANLIB_$toolSuffix") -Value (Join-Path $prebuiltBin ('llvm-ranlib' + $binExeSuffix))
    }

    $profileArgs = @()
    if ($Profile -eq 'release') { $profileArgs = @('--release') }

    Write-Output "[android] Building uam_ffi ($AbiName / $target, $Profile, API $ApiLevel)"
    Push-Location $cratesDir
    try {
        cargo build @profileArgs -p uam_ffi --target $target
        if ($LASTEXITCODE -ne 0) {
            throw "cargo build failed for $target (exit $LASTEXITCODE)."
        }
    } finally {
        Pop-Location
    }

    $profileDir = if ($Profile -eq 'release') { 'release' } else { 'debug' }
    $builtLibrary = Join-Path $cratesDir "target/$target/$profileDir/$libraryFileName"
    if (-not (Test-Path $builtLibrary)) {
        throw "Expected shared library was not produced: $builtLibrary"
    }

    $destinationDir = Join-Path $jniLibsRoot $AbiName
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    $destination = Join-Path $destinationDir $libraryFileName
    Copy-Item -Force $builtLibrary $destination

    Write-Output "[android] Built:  $builtLibrary"
    Write-Output "[android] Packed: $destination"

    $llvmNm = Join-Path $prebuiltBin ('llvm-nm' + $binExeSuffix)
    if (Test-Path $llvmNm) {
        Write-Output "[android] Exported UAM symbols ($AbiName):"
        & $llvmNm --dynamic --defined-only $destination |
            Select-String -Pattern 'uam_' |
            ForEach-Object { "  {0}" -f $_.Line.Trim() }
    }
}

$resolvedNdk = Resolve-NdkPath -Explicit $NdkPath
Write-Output "[android] NDK: $resolvedNdk"

$env:ANDROID_NDK_HOME = $resolvedNdk
$env:ANDROID_NDK_ROOT = $resolvedNdk

$abis = if ($Abi -eq 'all') { @('arm64-v8a', 'armeabi-v7a', 'x86_64') } else { @($Abi) }

foreach ($currentAbi in $abis) {
    Invoke-AndroidBuild -AbiName $currentAbi -NdkRoot $resolvedNdk -ApiLevel $Api
}

Write-Output '[android] Done. Run: flutter build apk --debug'
