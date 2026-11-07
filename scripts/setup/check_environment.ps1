$ErrorActionPreference = 'Stop'

Write-Output 'UAM Phase 0 environment check'
Write-Output ''

$commands = @(
    @{ Name = 'flutter'; Args = @('--version') },
    @{ Name = 'dart'; Args = @('--version') },
    @{ Name = 'rustc'; Args = @('--version') },
    @{ Name = 'cargo'; Args = @('--version') },
    @{ Name = 'git'; Args = @('--version') }
)

foreach ($command in $commands) {
    $resolved = Get-Command $command.Name -ErrorAction SilentlyContinue
    if ($null -eq $resolved) {
        Write-Output "MISSING: $($command.Name)"
        continue
    }
    $version = & $command.Name @($command.Args) 2>&1 | Select-Object -First 1
    Write-Output "OK: $($command.Name) -> $version"
}

Write-Output ''
Write-Output 'Rust toolchains:'
rustup show
Write-Output ''
Write-Output 'Run the following for the full platform report:'
Write-Output '  flutter doctor -v'
Write-Output '  python scripts/test/validate_presets.py'
Write-Output '  powershell -ExecutionPolicy Bypass -File scripts/build/build_rust.ps1'