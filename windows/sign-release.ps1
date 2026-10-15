param([string]$PublishDirectory, [string]$InstallerPath, [switch]$RequireSignature)
$ErrorActionPreference = 'Stop'
if (-not $env:WINDOWS_SIGNING_CERTIFICATE_BASE64 -or -not $env:WINDOWS_SIGNING_CERTIFICATE_PASSWORD) {
    if ($RequireSignature) { throw 'Windows Authenticode signing secrets are missing.' }
    Write-Host 'Development build: Windows signing is not configured.'
    return
}
$certificate = Join-Path ([IO.Path]::GetTempPath()) ("hdrive-signing-" + [guid]::NewGuid() + '.pfx')
try {
    [IO.File]::WriteAllBytes($certificate, [Convert]::FromBase64String($env:WINDOWS_SIGNING_CERTIFICATE_BASE64))
    $tool = Get-ChildItem "${env:ProgramFiles(x86)}\Windows Kits\10\bin\*\x64\signtool.exe" |
        Sort-Object FullName -Descending | Select-Object -First 1
    if ($null -eq $tool) { throw 'signtool.exe was not found.' }
    $targets = if ($InstallerPath) { @($InstallerPath) } else { @((Join-Path $PublishDirectory 'HDrive.exe'), (Join-Path $PublishDirectory 'HDrive.dll')) }
    foreach ($target in $targets) {
        & $tool.FullName sign /fd SHA256 /tr http://timestamp.digicert.com /td SHA256 /f $certificate /p $env:WINDOWS_SIGNING_CERTIFICATE_PASSWORD $target
        if ($LASTEXITCODE -ne 0) { throw "Signing failed: $target" }
        & $tool.FullName verify /pa /all $target
        if ($LASTEXITCODE -ne 0) { throw "Signature verification failed: $target" }
    }
} finally {
    if (Test-Path -LiteralPath $certificate) { Remove-Item -LiteralPath $certificate -Force }
}
