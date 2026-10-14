param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [string]$Version = 'source',
    [switch]$VerifyMigration
)

$ErrorActionPreference = 'Stop'
if ($env:GITHUB_ACTIONS -ne 'true') {
    throw 'This fixture changes test profile files and must run on an isolated GitHub Actions runner.'
}
$appData = Join-Path $env:LOCALAPPDATA 'HDrive'
$backup = "$appData-regression-backup-$([Guid]::NewGuid())"
$hadProfile = Test-Path -LiteralPath $appData
if ($hadProfile) { Move-Item -LiteralPath $appData -Destination $backup }
$server = $null

function Assert-MigratedProfile {
    $accounts = @(Get-Content -LiteralPath (Join-Path $appData 'servers.json') -Raw | ConvertFrom-Json)
    if ($accounts.Count -ne 1) { throw 'Migration did not preserve exactly one legacy account.' }
    $account = $accounts[0]
    foreach ($name in @('Id', 'Name', 'ServerURL', 'Username', 'AutoSyncEnabled')) {
        if ($account.$name -ne $legacy[$name]) { throw "Migration changed legacy field '$name'." }
    }
    if ($account.Protocol -ne 0 -or -not $account.IsConnected -or $account.Password -ne '') {
        throw 'Migration did not preserve WebDAV defaults and password storage.'
    }
    $activeId = (Get-Content -LiteralPath (Join-Path $appData 'active_server_id.txt') -Raw).Trim()
    if ($activeId -ne $account.Id) { throw 'Migration did not preserve the active account.' }
    foreach ($name in @('ProviderName', 'GlyphIcon', 'Subtitle', 'IsActive', 'ConnectionStatusText', 'ConnectionActionText', 'StatusDotBrush', 'StatusTextBrush', 'StatusBgBrush')) {
        if ($account.PSObject.Properties.Name -contains $name) {
            throw "Presentation property '$name' was written to servers.json."
        }
    }
    Write-Host 'PASS: Legacy account data and active account were migrated without presentation properties.'
}

try {
    $server = Start-Process -FilePath python -ArgumentList (Join-Path $PSScriptRoot 'startup-test-server.py') -PassThru
    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        try {
            Invoke-WebRequest -Uri http://127.0.0.1:18087/ -TimeoutSec 1 | Out-Null
            $ready = $true
            break
        } catch { Start-Sleep -Milliseconds 200 }
    }
    if (-not $ready) { throw 'The loopback WebDAV fixture did not start.' }

    New-Item -ItemType Directory -Path $appData | Out-Null
    $legacy = @{
        Id = 'legacy-webdav'; Name = 'Startup WebDAV'; ServerURL = 'http://127.0.0.1:18087/dav'
        Username = 'startup-fixture'; Password = ''; AutoSyncEnabled = $false
    }
    $legacy | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $appData 'config.json') -Encoding UTF8
    @(@{ Name = 'Fixture folder'; Path = 'fixture' }) | ConvertTo-Json -AsArray |
        Set-Content -LiteralPath (Join-Path $appData 'pinned_folders.json') -Encoding UTF8
    Write-Host "Testing $Version with the v1.2.7 config.json format"
    & (Join-Path $PSScriptRoot 'test-startup.ps1') -ExePath $ExePath -ReportDirectory "windows/upgrade-report/legacy-$Version" -ObserveSeconds 15

    if ($VerifyMigration) {
        Assert-MigratedProfile
        Write-Host 'Restarting the migrated profile to verify subsequent launches'
        & (Join-Path $PSScriptRoot 'test-startup.ps1') -ExePath $ExePath -ReportDirectory "windows/upgrade-report/restart-$Version" -ObserveSeconds 15
        Assert-MigratedProfile
    }

    if ($Version -ne 'v1.2.7') {
        Remove-Item -LiteralPath (Join-Path $appData 'crash.log') -ErrorAction SilentlyContinue
        $legacy.Protocol = 0
        $legacy.IsConnected = $true
        @($legacy) | ConvertTo-Json -AsArray |
            Set-Content -LiteralPath (Join-Path $appData 'servers.json') -Encoding UTF8
        'legacy-webdav' | Set-Content -LiteralPath (Join-Path $appData 'active_server_id.txt') -Encoding UTF8
        Write-Host "Testing $Version with the multi-account servers.json format"
        & (Join-Path $PSScriptRoot 'test-startup.ps1') -ExePath $ExePath -ReportDirectory "windows/upgrade-report/servers-$Version" -ObserveSeconds 15
    }
} finally {
    if ($null -ne $server -and -not $server.HasExited) { Stop-Process -Id $server.Id -Force }
    if (Test-Path -LiteralPath $appData) { Remove-Item -LiteralPath $appData -Recurse -Force }
    if ($hadProfile) { Move-Item -LiteralPath $backup -Destination $appData }
}
