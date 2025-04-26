Set-ExecutionPolicy Bypass -Scope Process -Force
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#For install:
#iwr -useb https://raw.githubusercontent.com/trunghieuth10/public/refs/heads/main/telegraf_install.ps1 | iex

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName System.IO.Compression.FileSystem

function Ensure-AdminRights {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
        Write-Host "Restarting script with Administrator privileges..."
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
        Start-Process powershell -Verb RunAs -ArgumentList $arguments
        exit
    }
}

function Extract-InnerFolder {
    param (
        [string]$zipPath,
        [string]$targetPath
    )
    try {
        $tempExtract = Join-Path $env:TEMP "telegraf_temp_extract"
        if (Test-Path $tempExtract) { Remove-Item $tempExtract -Recurse -Force }
        New-Item -Path $tempExtract -ItemType Directory | Out-Null

        [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $tempExtract)

        $innerFolder = Get-ChildItem -Path $tempExtract | Where-Object { $_.PSIsContainer } | Select-Object -First 1
        if (-not $innerFolder) { throw "No inner folder found inside zip." }

        $files = Get-ChildItem -Path $innerFolder.FullName -Recurse -File
        foreach ($file in $files) {
            $relativePath = $file.FullName.Substring($innerFolder.FullName.Length + 1)
            $destinationPath = Join-Path $targetPath $relativePath

            $destinationDir = Split-Path $destinationPath -Parent
            if (-not (Test-Path $destinationDir)) {
                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            }

            Copy-Item -Path $file.FullName -Destination $destinationPath -Force
        }

        Remove-Item $tempExtract -Recurse -Force
    } catch {
        throw "Failed to extract ZIP: $_"
    }
}

function Get-Architecture {
    $arch = (Get-CimInstance Win32_OperatingSystem).OSArchitecture
    if ($arch -match "64") {
        if ([Environment]::Is64BitOperatingSystem) {
            $processor = (Get-CimInstance Win32_Processor).Name
            if ($processor -match "ARM") {
                return "arm64"
            } else {
                return "amd64"
            }
        }
    }
    elseif ($arch -match "32") {
        return "i386"
    }
    throw "Unsupported architecture: $arch"
}

function Get-TelegrafDownloadUrl {
    $apiUrl = "https://api.github.com/repos/influxdata/telegraf/releases/latest"
    $releaseData = Invoke-RestMethod -Uri $apiUrl
    $body = $releaseData.body
    $arch = Get-Architecture

    Write-Host "Detected architecture: $arch"

    $pattern = "https:\/\/dl\.influxdata\.com\/telegraf\/releases\/telegraf-.*_windows_${arch}\.zip"

    if ($body -match $pattern) {
        return $Matches[0]
    } else {
        throw "Download URL for architecture $arch not found in API body!"
    }
}

function Download-File {
    param (
        [string]$url,
        [string]$destination
    )
    try {
        if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
            Write-Host "Trying BITS download..."
            Start-BitsTransfer -Source $url -Destination $destination -Priority Foreground
        } else {
            throw "BITS not available"
        }
    } catch {
        Write-Warning "BITS failed: $($_.Exception.Message). Falling back to Invoke-WebRequest..."
        try {
            Invoke-WebRequest -Uri $url -OutFile $destination
        } catch {
            throw "Fallback download with Invoke-WebRequest failed: $($_.Exception.Message)"
        }
    }

    if (-not (Test-Path $destination)) {
        throw "Download failed: File not found at $destination"
    }
}

function Stop-And-Disable-ServicesByName {
    param (
        [string]$NameKeyword = "telegraf"
    )

    # Get all services that match the name keyword
    $services = Get-Service | Where-Object { $_.Name -like "*$NameKeyword*" }

    if ($services.Count -eq 0) {
        Write-Output "No services found with keyword: '$NameKeyword'"
        return
    }

    foreach ($service in $services) {
        Write-Output "Processing service: $($service.Name)"
        
        # Stop the service if it's running
        if ($service.Status -eq 'Running') {
            Write-Output " - Stopping service..."
            Stop-Service -Name $service.Name -Force
        } else {
            Write-Output " - Service is already stopped."
        }

        # Disable the service
        Write-Output " - Disabling service..."
        Set-Service -Name $service.Name -StartupType Disabled
    }

    Write-Output "Done stopping and disabling services with keyword '$NameKeyword'."
}

function Install-Telegraf {
    $installPath = "C:\Program Files\InfluxData\telegraf"
    $exePath = Join-Path $installPath "telegraf.exe"

    if (Test-Path $exePath) {
        Write-Host "Existing Telegraf installation found. Uninstalling..."
        try {
            Stop-And-Disable-ServicesByName -NameKeyword "telegraf"
            & $exePath service uninstall
        } catch {
            Write-Warning "Error during service removal: $_"
        }
        Remove-Item $installPath -Recurse -Force
    }

    New-Item -Path $installPath -ItemType Directory -Force | Out-Null
    
    try {
        Write-Host "Checking for local Telegraf file in current directory..."
    
        $currentDir = Get-Location
        $localZip = Get-ChildItem -Path $currentDir -Filter "telegraf-*.zip" | Select-Object -First 1
    
        if ($localZip) {
            Write-Host "Found local ZIP: $($localZip.Name). Using it.."
            $zipFile = $localZip.FullName
        } else {
            Write-Host "No local ZIP found. Proceeding to download latest Telegraf release..."
            $downloadUrl = Get-TelegrafDownloadUrl
            $fileName = Split-Path $downloadUrl -Leaf
            $zipFile = Join-Path $env:TEMP $fileName
    
            Write-Host "Downloading Telegraf from: $downloadUrl"
            Download-File -url $downloadUrl -destination $zipFile
        }
    }
    catch {
        Write-Host "An error occurred while checking for a local ZIP. Falling back to download."
    
        $downloadUrl = Get-TelegrafDownloadUrl
        $fileName = Split-Path $downloadUrl -Leaf
        $zipFile = Join-Path $env:TEMP $fileName
    
        Write-Host "Downloading Telegraf from: $downloadUrl"
        Download-File -url $downloadUrl -destination $zipFile
    }
    
    Write-Host "Extracting package..."
    Extract-InnerFolder -zipPath $zipFile -targetPath $installPath
    Remove-Item $zipFile -Force

    if (-not (Test-Path $exePath)) {
        throw "Telegraf executable not found after extraction."
    }

    $token = "IclOtLROVMfMof3zLJIGqXVzmL_ghvQOVLWGN3psEKI6FCQX3HOvBGQ1AH4I064eDp26o_DVk8UoeG3v9uaUTA=="
    $configUrl = "https://us-east-1-1.aws.cloud2.influxdata.com/api/v2/telegrafs/0ec56c3e33489000"

    $envFile = Join-Path $installPath ".env"
    "INFLUX_TOKEN=$token" | Out-File -FilePath $envFile -Encoding ascii -Force
    [System.Environment]::SetEnvironmentVariable("INFLUX_TOKEN", $token, "Machine")
    $env:INFLUX_TOKEN = $token

    Write-Host "Installing Telegraf as a Windows Service..."
    & $exePath --config "$configUrl" --service-name telegraf service install
    
    Set-Service -Name telegraf -StartupType Automatic
    Start-Service telegraf

    Write-Host "Telegraf service installed and started successfully."
}

try {
    Ensure-AdminRights
    Install-Telegraf
    Write-Host "`nTelegraf installation completed successfully."
} catch {
    Write-Error "Error occurred: $_"
}
