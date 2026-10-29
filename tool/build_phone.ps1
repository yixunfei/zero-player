param(
    [switch]$SkipBuild,
    [double]$MaxMiB = 70,
    [string]$OutputDirectory = 'artifacts/phone'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
Push-Location $projectRoot
try {
    if (!$SkipBuild) {
        & flutter build apk --release --target-platform android-arm64
        if ($LASTEXITCODE -ne 0) { throw 'Phone release build failed.' }
    }
    $apk = Join-Path $projectRoot 'build/app/outputs/flutter-apk/app-release.apk'
    & python tool/verify_apk.py $apk --abis arm64-v8a --max-mib $MaxMiB --compressed-native
    if ($LASTEXITCODE -ne 0) { throw 'Phone APK verification failed.' }
    $destination = if ([IO.Path]::IsPathRooted($OutputDirectory)) {
        $OutputDirectory
    } else {
        Join-Path $projectRoot $OutputDirectory
    }
    New-Item -ItemType Directory -Force -Path $destination | Out-Null
    $output = Join-Path $destination 'zero-player-android-arm64.apk'
    if (Test-Path -LiteralPath $output) {
        if ((Get-FileHash -LiteralPath $output).Hash -ne (Get-FileHash -LiteralPath $apk).Hash) {
            throw 'Phone artifact already exists with different content; select a new output directory.'
        }
    } else {
        Copy-Item -LiteralPath $apk -Destination $output
    }
    $hash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
    "$hash  zero-player-android-arm64.apk" | Set-Content -LiteralPath (Join-Path $destination 'SHA256SUMS.txt') -Encoding ascii
    Write-Output $output
} finally { Pop-Location }
