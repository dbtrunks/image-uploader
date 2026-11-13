param(
    [string]$Version = "latest"
)

$ErrorActionPreference = "Stop"
$repository = "dbtrunks/image-uploader"
$assetName = "ImageUploader-win-x64.tar.gz"
$installDirectory = Join-Path $env:ProgramFiles "ImageUploader"
$dataDirectory = Join-Path $env:ProgramData "ImageUploader"
$serviceName = "ImageUploader"
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

    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($service -and $service.Status -ne [System.ServiceProcess.ServiceControllerStatus]::Stopped) {
        Stop-Service -Name $serviceName -Force
        $service.WaitForStatus(
            [System.ServiceProcess.ServiceControllerStatus]::Stopped,
            [TimeSpan]::FromSeconds(30))
    }

    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        Get-CimInstance Win32_Process -Filter "Name='ImageUploader.exe'" |
            Where-Object { $_.ExecutablePath -eq (Join-Path $installDirectory "ImageUploader.exe") } |
            ForEach-Object {
                Stop-Process -Id $_.ProcessId -Force
                Wait-Process -Id $_.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
            }
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
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

    $executable = Join-Path $installDirectory "ImageUploader.exe"
    if (-not $service) {
        New-Service -Name $serviceName -DisplayName "Image Uploader" `
            -Description "Image Uploader file upload service." `
            -BinaryPathName ('"{0}"' -f $executable) `
            -StartupType Automatic | Out-Null
    }

    & sc.exe config $serviceName "binPath= `"$executable`"" "start= auto" | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Nie udało się skonfigurować usługi Windows $serviceName."
    }

    $serviceRegistryPath = "HKLM:\SYSTEM\CurrentControlSet\Services\$serviceName"
    $currentEnvironment = (Get-ItemProperty -Path $serviceRegistryPath -Name Environment -ErrorAction SilentlyContinue).Environment
    $serviceEnvironment = @($currentEnvironment | Where-Object { $_ -notmatch '^ASPNETCORE_URLS=' })
    $serviceEnvironment += "ASPNETCORE_URLS=http://0.0.0.0:8282"
    New-ItemProperty -Path $serviceRegistryPath -Name Environment -PropertyType MultiString `
        -Value $serviceEnvironment -Force | Out-Null

    if (-not (Get-NetFirewallRule -DisplayName $firewallRuleName -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName $firewallRuleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort 8282 -Profile Domain,Private | Out-Null
    }

    Start-Service -Name $serviceName
    Write-Output 'Instalacja zakonczona. Otworz http://<IP-komputera>:8282/'
    Write-Output ('Service status: Get-Service -Name {0}' -f $serviceName)
} finally {
    if (Test-Path $temporaryDirectory) {
        Remove-Item $temporaryDirectory -Recurse -Force
    }
}
