param([string]$ExePath)

if (-not $ExePath) {
    $localExe = Join-Path $PSScriptRoot 'HDrive.exe'
    $ExePath = if (Test-Path -LiteralPath $localExe) { $localExe } else { "$env:LOCALAPPDATA\Programs\HDrive\HDrive.exe" }
}

$ErrorActionPreference = 'Stop'
$reportPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'HDrive-diagnostics.txt'
$report = [System.Collections.Generic.List[string]]::new()
$report.Add("HDrive startup diagnostics - $(Get-Date -Format o)")
$report.Add("Windows: $([Environment]::OSVersion.VersionString)")
$report.Add("64-bit OS: $([Environment]::Is64BitOperatingSystem)")
$report.Add("Executable: $ExePath")
$started = Get-Date

try {
    $exe = Get-Item -LiteralPath $ExePath
    $directory = $exe.DirectoryName
    foreach ($name in @('HDrive.dll', 'HDrive.runtimeconfig.json', 'Microsoft.UI.Xaml.dll', 'coreclr.dll', 'hostfxr.dll')) {
        $report.Add("File ${name}: $(Test-Path -LiteralPath (Join-Path $directory $name))")
    }
    $runtimeConfig = Join-Path $directory 'HDrive.runtimeconfig.json'
    if (Test-Path -LiteralPath $runtimeConfig) {
        $report.Add((Get-Content -LiteralPath $runtimeConfig -Raw))
    }
    $process = Start-Process -FilePath $exe.FullName -WorkingDirectory $directory -PassThru
    $exited = $process.WaitForExit(10000)
    if ($exited) {
        $report.Add("Exited within 10 seconds. Exit code: $($process.ExitCode) (0x$('{0:X8}' -f $process.ExitCode))")
    } else {
        $process.Refresh()
        $report.Add("Still running after 10 seconds. PID: $($process.Id); Window handle: $($process.MainWindowHandle)")
    }
} catch {
    $report.Add("Launch error: $($_.Exception.ToString())")
}

# Native loader failures can happen before App.LogCrash is available.
Start-Sleep -Seconds 3
try {
    $events = Get-WinEvent -FilterHashtable @{
        LogName = 'Application'
        StartTime = $started.AddSeconds(-2)
        Id = @(1000, 1001, 1026, 33, 59)
    } -ErrorAction Stop | Where-Object { $_.Message -match '(?i)HDrive' }
    foreach ($event in $events) {
        $report.Add("Event $($event.Id) [$($event.ProviderName)] $($event.TimeCreated)`r`n$($event.Message)")
    }
} catch {
    $report.Add("Event query: $($_.Exception.Message)")
}

$crashLog = Join-Path $env:LOCALAPPDATA 'HDrive\crash.log'
if (Test-Path -LiteralPath $crashLog) {
    $report.Add('Last 100 lines of crash.log (may include earlier launches):')
    $report.Add((Get-Content -LiteralPath $crashLog -Tail 100) -join "`r`n")
} else {
    $report.Add('No crash.log. Failure may have occurred before managed app initialization.')
}
$report | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host "Report saved: $reportPath"
