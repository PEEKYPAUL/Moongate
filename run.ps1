<#
.SYNOPSIS
    Builds and runs the Moongate Flutter app on a connected Android device.
    Fixes the Java AF_UNIX issue caused by Windows 8.3 short names in TEMP path.
#>

# Ensure C:\tmp exists (needed for Java AF_UNIX socket workaround)
if (-not (Test-Path "C:\tmp")) {
    New-Item -ItemType Directory -Force -Path "C:\tmp" | Out-Null
    Write-Host "Created C:\tmp for Java temp files" -ForegroundColor Green
}

# Fix environment: TEMP path with ~ (8.3 short names) breaks Java AF_UNIX sockets
$env:TEMP = "C:\tmp"
$env:TMP  = "C:\tmp"
$env:GRADLE_OPTS = "-Djava.io.tmpdir=C:\tmp"

# Use JDK 17 (JDK 21's AF_UNIX impl also fails on this machine)
$jdk17 = "C:\Users\PaulSharman\jdk17\jdk-17.0.14+7"
$env:JAVA_HOME = $jdk17
$env:Path = "$jdk17\bin;$env:Path"

# Flutter SDK
$flutter = "C:\Users\PaulSharman\.puro\envs\stable\flutter\bin\flutter.bat"

Write-Host "Building Moongate..." -ForegroundColor Cyan
Write-Host "  JDK: $jdk17" -ForegroundColor Gray
Write-Host "  TEMP: C:\tmp" -ForegroundColor Gray

Set-Location "C:\Projects\moongate\mobile"
& $flutter @args