param(
    [string] $OutputPath = (Join-Path $PSScriptRoot '..\..\docs\platform\windows-endpoint-inventory.txt')
)

$ErrorActionPreference = 'Stop'
$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

$timestamp = (Get-Date).ToUniversalTime().ToString('o')
$endpoints = Get-PnpDevice -Class AudioEndpoint -ErrorAction Stop |
    Select-Object Status, FriendlyName, InstanceId

$lines = @(
    '# UAM Windows endpoint inventory',
    "# Captured UTC: $timestamp",
    '# This is an OS inventory probe, not a WASAPI integration test.',
    '# It does not prove endpoint activation, default-role selection, or DSP routing.',
    ''
)
$lines += ($endpoints | Format-Table -AutoSize | Out-String -Width 240)
$lines | Set-Content -Encoding UTF8 $OutputPath
Write-Output "Wrote endpoint inventory: $OutputPath"
