param(
    [string] $LibraryPath = (Join-Path $PSScriptRoot '..\..\app\flutter\windows\runner\native\uam_ffi.dll')
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path $LibraryPath)) {
    throw "Rust bridge library not found at $LibraryPath. Run scripts/build/build_rust.ps1 first."
}
Write-Output "Native library exists: $LibraryPath"
Write-Output "Flutter integration test: cd app/flutter; flutter test test/integration/rust_bridge_test.dart"
