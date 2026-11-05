# Gamepad firewall setup. Run once on the PC that hosts server.py.
# Usage:  powershell -ExecutionPolicy Bypass -File .\setup_firewall.ps1
$ErrorActionPreference = 'Stop'
$ruleName = 'PhonePad UDP 7777'

$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'Requesting administrator access...'
    $arguments = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', "`"$PSCommandPath`""
    )
    Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $arguments
    exit
}

if (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue) {
    Write-Host "Firewall rule already exists: $ruleName"
} else {
    New-NetFirewallRule `
        -DisplayName $ruleName `
        -Direction Inbound `
        -Protocol UDP `
        -LocalPort 7777 `
        -Action Allow `
        -Profile Any | Out-Null
    Write-Host "Created inbound UDP 7777 rule: $ruleName"
}

Write-Host ''
Write-Host 'If pairing still fails, open:'
Write-Host '  Windows Security > Firewall & network protection >'
Write-Host '  Allow an app through firewall'
Write-Host 'and remove any block entries for python.exe.'
Write-Host ''
Write-Host 'Then start Gamepad with:'
Write-Host '  start-server.bat'
