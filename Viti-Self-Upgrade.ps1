# Auto Upgrade Script for Tamanu Servers
# ---------------------------------------
# Author: Harnesh Raman
# Date: 2025-05-24
# Description: This script automates the upgrade process for Tamanu servers.

# Create a log file and redirect all output to it
$logFile = "C:\AutoDeploy\upgrade_log.txt"
Start-Transcript -Path $logFile

# Function to handle errors and exit if necessary
function Handle-Error {
    param (
        [string]$message
    )
    Write-Host "Error: $message" -ForegroundColor Red
    Stop-Transcript
    exit 1
}

# Helper function to call scripts and check for errors
function Call-Script {
    param (
        [string]$scriptPath
    )
    Write-Host "Running $scriptPath..."
    & $scriptPath
    if ($LASTEXITCODE -ne 0) {
        $continue = Read-Host "Failed to run $scriptPath. Do you want to continue? (Y/N)"
        if ($continue -ne "Y") {
            Write-Host "Exiting script." -ForegroundColor Red
            Stop-Transcript
            exit 1
        }
    }
}

# Step 1: Create AutoDeploy folder
$autoDeployPath = "C:\AutoDeploy"
Write-Host "Checking if AutoDeploy folder exists..."
if (-not (Test-Path -Path $autoDeployPath -PathType Container)) {
    Write-Host "Creating AutoDeploy folder..."
    mkdir $autoDeployPath
    if ($LASTEXITCODE -ne 0) {
        Handle-Error "Failed to create AutoDeploy folder."
    }
} else {
    Write-Host "AutoDeploy folder already exists: $autoDeployPath"
}

# Step 2: Download bestool.exe
$bestoolPath = "$autoDeployPath\bestool.exe"
Write-Host "Checking if bestool.exe exists..."
if (-not (Test-Path -Path $bestoolPath)) {
    Write-Host "Downloading bestool.exe..."
    try {
        Invoke-WebRequest -Uri "https://tools.ops.tamanu.io/bestool/latest/x86_64-pc-windows-msvc/bestool.exe" -OutFile $bestoolPath -ErrorAction Stop
        Write-Host "Downloaded bestool.exe to $bestoolPath"
    } catch {
        Handle-Error "Failed to download bestool.exe."
    }
} else {
    Write-Host "bestool.exe already exists: $bestoolPath"
}

# Prompt for user input and declare variables
$platform = Read-Host "Enter platform (central/facility)"
$currentVersion = Read-Host "Enter current server version (e.g., 2.1.6)"
$upgradeVersion = Read-Host "Enter upgrade version (e.g., 2.8.2)"

# Step 3: Download %platform% $upgradeVersion
Write-Host "Downloading $platform $upgradeVersion..."
C:\AutoDeploy\bestool.exe tamanu download $platform $upgradeVersion
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to download $platform $upgradeVersion."
    Stop-Transcript
    exit 1
}

# Step 4: Download Web $upgradeVersion
Write-Host "Downloading Web $upgradeVersion..."
C:\AutoDeploy\bestool.exe tamanu download web $upgradeVersion
if ($LASTEXITCODE -ne 0) {
    Write-Host "Error: Failed to download Web $upgradeVersion."
    Stop-Transcript
    exit 1
}

# Step 5: Check if there are any services running
Write-Host "Checking if there are any services running..."
$services = pm2 status
if ($LASTEXITCODE -eq 0 -and $services -match "online") {
    Write-Host "Services are running. Deleting old servers..."
    pm2 delete all
    if ($LASTEXITCODE -ne 0) {
        Handle-Error "Failed to delete old servers."
    }
    pm2 save --force
    if ($LASTEXITCODE -ne 0) {
        Handle-Error "Failed to save PM2 state after deleting servers."
    }
} else {
    Write-Host "No services are running. Skipping step 5."
}

# Step 6: Run backup.bat
Write-Host "Running backup.bat..."
cd C:\backup
.\backup.bat
if ($LASTEXITCODE -ne 0) {
    $continue = Read-Host "Failed to run backup.bat. Do you want to continue? (Y/N)"
    if ($continue -ne "Y") {
        Handle-Error "Failed to run backup.bat."
    }
}

# Step 7: Copy local.json5 from older build to new build
$sourcePath = "C:\Tamanu\release-v$currentVersion\packages\$platform-server\config\local.json5"
$destinationPath = "C:\Tamanu\release-v$upgradeVersion\packages\$platform-server\config"
Write-Host "Copying local.json5 from older build to new build..."

# Check if local.json file exists in the destination path, if yes, delete it
$localJsonPath = Join-Path $destinationPath "local.json"
if (Test-Path -Path $localJsonPath -PathType Leaf) {
    Write-Host "Deleting existing local.json file..."
    Remove-Item -Path $localJsonPath -Force
    if ($LASTEXITCODE -ne 0) {
        Handle-Error "Failed to delete existing local.json file."
    }
}

# Copy local.json5 file from the source to the destination
Copy-Item -Path $sourcePath -Destination $destinationPath -Force
if ($LASTEXITCODE -ne 0) {
    Handle-Error "Failed to copy local.json5."
}


# Step 8: Install dependencies with yarn --prod
Write-Host "Installing dependencies with yarn --prod..."
cd "C:\Tamanu\release-v$upgradeVersion"
yarn --prod
if ($LASTEXITCODE -ne 0) {
    Handle-Error "Failed to install dependencies."
}

# Step 9: Run database migrations
Write-Host "Running database migrations..."
cd "C:\Tamanu\release-v$upgradeVersion\packages\$platform-server"
$attempt = 1
$maxAttempts = 3
while ($attempt -le $maxAttempts) {
    try {
        node dist migrate
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully ran database migrations."
            break
        } else {
            Write-Host "Failed to run database migrations (Attempt $attempt)."
            $attempt++
        }
    } catch {
        Handle-Error "Failed to run database migrations."
    }
}
if ($attempt -gt $maxAttempts) {
    Write-Host "All attempts to run database migrations failed. Skipping migrations."
}

# Step 10: Start the application with PM2
Write-Host "Starting the application with PM2..."
cd "C:\Tamanu\release-v$upgradeVersion"
pm2 start pm2.config.cjs
if ($LASTEXITCODE -ne 0) {
    Handle-Error "Failed to start the application with PM2."
}
pm2 save --force
if ($LASTEXITCODE -ne 0) {
    Handle-Error "Failed to save PM2 state after starting the application."
}

Write-Host "Upgrade completed successfully."
Stop-Transcript
pause
exit 0
