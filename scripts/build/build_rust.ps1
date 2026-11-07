param(
    [ValidateSet('debug', 'release')]
    [string] $Profile = 'debug'
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$cratesDir = Join-Path $repoRoot 'crates'
$flutterDir = Join-Path $repoRoot 'app\flutter'
$toolchain = 'stable-x86_64-pc-windows-gnu'

# The host has Rust's GNU target and self-contained linker but no MSVC linker.
# rust-lld avoids the WinLibs path-with-spaces issue and does not install anything.
$env:RUSTUP_TOOLCHAIN = $toolchain
$env:RUSTFLAGS = '-C linker=rust-lld -C link-self-contained=yes'

Push-Location $cratesDir
try {
    if ($Profile -eq 'release') {
        cargo build --release -p uam_ffi
        $source = Join-Path $cratesDir 'target\release\uam_ffi.dll'
    } else {
        cargo build -p uam_ffi
        $source = Join-Path $cratesDir 'target\debug\uam_ffi.dll'
    }
} finally {
    Pop-Location
}

$destinationDir = Join-Path $flutterDir 'windows\runner\native'
New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
$destination = Join-Path $destinationDir 'uam_ffi.dll'
Copy-Item -Force $source $destination
Write-Output "Built Rust FFI library: $source"
Write-Output "Copied Flutter runtime library: $destination"
