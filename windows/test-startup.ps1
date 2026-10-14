param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [Parameter(Mandatory = $true)][string]$ReportDirectory,
    [int]$TimeoutSeconds = 30,
    [int]$ObserveSeconds = 3
)

$ErrorActionPreference = 'Stop'
$exe = Get-Item -LiteralPath $ExePath
$reportDirectoryPath = [IO.Path]::GetFullPath($ReportDirectory)
New-Item -ItemType Directory -Path $reportDirectoryPath -Force | Out-Null
$report = [System.Collections.Generic.List[string]]::new()
$started = Get-Date
$process = $null
$failure = $null
$crashLog = Join-Path $env:LOCALAPPDATA 'HDrive\crash.log'
$originalLogLength = if (Test-Path -LiteralPath $crashLog) { (Get-Item -LiteralPath $crashLog).Length } else { 0 }

try {
    $report.Add("Start: $($started.ToString('o'))")
    $report.Add("Windows: $([Environment]::OSVersion.VersionString)")
    $report.Add("Executable: $($exe.FullName)")
    $process = Start-Process -FilePath $exe.FullName -WorkingDirectory $exe.DirectoryName -PassThru
    $deadline = $started.AddSeconds($TimeoutSeconds)
    $ready = $false
    do {
        $process.Refresh()
        if ($process.HasExited) {
            throw "HDrive exited before opening its main window: $($process.ExitCode) (0x$('{0:X8}' -f $process.ExitCode))."
        }
        # A crash MessageBox also creates a window. Require the actual app title.
        if ($process.MainWindowHandle -ne [IntPtr]::Zero -and $process.MainWindowTitle -eq 'HDrive') {
            $ready = $true
            break
        }
        Start-Sleep -Milliseconds 250
    } while ((Get-Date) -lt $deadline)

    if (-not $ready) {
        throw "HDrive did not open its main window within $TimeoutSeconds seconds. Last window title: '$($process.MainWindowTitle)'."
    }

    # Allow first layout and deferred startup callbacks to run before passing.
    Start-Sleep -Seconds $ObserveSeconds
    $process.Refresh()
    if ($process.HasExited -or $process.MainWindowHandle -eq [IntPtr]::Zero -or $process.MainWindowTitle -ne 'HDrive') {
        throw 'HDrive lost its main window immediately after startup.'
    }
    if ((Test-Path -LiteralPath $crashLog) -and (Get-Item -LiteralPath $crashLog).Length -gt $originalLogLength) {
        throw 'HDrive recorded a startup error in crash.log.'
    }
    $report.Add("PASS: Main window '$($process.MainWindowTitle)' opened and remained available. PID: $($process.Id).")
} catch {
    $failure = $_
    $report.Add("FAIL: $($_.Exception.ToString())")
} finally {
    if (Test-Path -LiteralPath $crashLog) {
        Copy-Item -LiteralPath $crashLog -Destination (Join-Path $reportDirectoryPath 'crash.log')
    }
    try {
        # Loader and native crashes can occur before managed logging exists.
        Start-Sleep -Seconds 2
        Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = $started.AddSeconds(-2) } -ErrorAction Stop |
            Where-Object { $_.Message -match '(?i)HDrive' } |
            Select-Object TimeCreated, Id, ProviderName, Message |
            Format-List | Out-String |
            Set-Content -LiteralPath (Join-Path $reportDirectoryPath 'windows-events.txt') -Encoding UTF8
    } catch {
        $report.Add("Event query: $($_.Exception.Message)")
    }
    # Stop only the test process, never another user's running HDrive instance.
    if ($null -ne $process) {
        $process.Refresh()
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
        }
    }
    $report | Set-Content -LiteralPath (Join-Path $reportDirectoryPath 'startup.txt') -Encoding UTF8
    $report | ForEach-Object { Write-Host $_ }
}
if ($null -ne $failure) {
    throw $failure
}
