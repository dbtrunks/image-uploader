param(
    [string]$Version = "latest"
)

$ErrorActionPreference = "Stop"
$repository = "dbtrunks/image-uploader"
$assetName = "ImageUploader-win-x64.tar.gz"
$installDirectory = Join-Path $env:ProgramFiles "ImageUploader"
$dataDirectory = Join-Path $env:ProgramData "ImageUploader"
$taskName = "ImageUploader"
$firewallRuleName = "ImageUploader (TCP 8282)"

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Uruchom PowerShell jako administrator."
}

if ($Version -ne "latest" -and $Version -notmatch '^v[0-9A-Za-z][0-9A-Za-z._-]*$') {
    throw "Nieprawidłowy tag wydania: $Version (oczekiwano np. v1.2.3 lub latest)."
}

if ($Version -eq "latest") {
    $downloadUrl = "https://github.com/$repository/releases/latest/download/$assetName"
} else {
    $downloadUrl = "https://github.com/$repository/releases/download/$Version/$assetName"
}

$temporaryDirectory = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid().ToString("N"))
$archivePath = Join-Path $temporaryDirectory $assetName
$stagingDirectory = Join-Path $temporaryDirectory "publish"

try {
    New-Item -ItemType Directory -Path $stagingDirectory -Force | Out-Null
    Invoke-WebRequest -Uri $downloadUrl -OutFile $archivePath

    & tar.exe -xzf $archivePath -C $stagingDirectory
    if ($LASTEXITCODE -ne 0) {
        throw "Nie udało się rozpakować archiwum wydania."
    }

    $executable = Join-Path $stagingDirectory "ImageUploader.exe"
    $settingsPath = Join-Path $stagingDirectory "appsettings.json"
    $wwwrootPath = Join-Path $stagingDirectory "wwwroot"
    if (-not (Test-Path $executable) -or -not (Test-Path $settingsPath) -or -not (Test-Path $wwwrootPath -PathType Container)) {
        throw "Archiwum wydania nie zawiera wymaganych plików aplikacji dla win-x64."
    }

    $oldSettingsPath = Join-Path $installDirectory "appsettings.json"
    if (Test-Path $oldSettingsPath) {
        Copy-Item $oldSettingsPath $settingsPath -Force
    }

    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Get-CimInstance Win32_Process -Filter "Name='ImageUploader.exe'" |
            Where-Object { $_.ExecutablePath -eq (Join-Path $installDirectory "ImageUploader.exe") } |
            ForEach-Object {
                Stop-Process -Id $_.ProcessId -Force
                Wait-Process -Id $_.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
            }
    }

    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    foreach ($destination in $settings.Upload.Destinations) {
        if ($destination.Path -eq "/var/lib/image-uploader/uploads") {
            $destination.Path = Join-Path $dataDirectory "uploads"
        } elseif ($destination.Path -eq "/var/lib/image-uploader/images") {
            $destination.Path = Join-Path $dataDirectory "images"
        }
    }
    $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding UTF8

    New-Item -ItemType Directory -Path $installDirectory, $dataDirectory, (Join-Path $dataDirectory "uploads"), (Join-Path $dataDirectory "images"), (Join-Path $dataDirectory "logs") -Force | Out-Null
    Copy-Item (Join-Path $stagingDirectory "*") $installDirectory -Recurse -Force

    $launcherPath = Join-Path $installDirectory "Start-ImageUploader.ps1"
    $logPath = Join-Path $dataDirectory "logs\image-uploader.log"
    $launcherContent = @(
        '$env:ASPNETCORE_URLS = "http://0.0.0.0:8282"'
        ('Set-Location "{0}"' -f $installDirectory)
        ('& "{0}\ImageUploader.exe" >> "{1}" 2>&1' -f $installDirectory, $logPath)
        'exit $LASTEXITCODE'
    ) -join [Environment]::NewLine
    Set-Content -Path $launcherPath -Value $launcherContent -Encoding UTF8

    $taskArguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $launcherPath + '"'
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArguments
    $trigger = New-ScheduledTaskTrigger -AtStartup
    $taskPrincipal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
    $settingsTask = New-ScheduledTaskSettingsSet -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero)
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $taskPrincipal -Settings $settingsTask -Force | Out-Null

    if (-not (Get-NetFirewallRule -DisplayName $firewallRuleName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $firewallRuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8282 -Profile Domain,Private | Out-Null
    }

    Start-ScheduledTask -TaskName $taskName
    Write-Output 'Instalacja zakonczona. Otworz http://<IP-komputera>:8282/'
    Write-Output ('Log aplikacji: {0}' -f $logPath)
} finally {
    if (Test-Path $temporaryDirectory) {
        Remove-Item $temporaryDirectory -Recurse -Force
    }
}
