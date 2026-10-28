param(
    [switch]$WindowsOnly,
    [string]$Iscc = "$PSScriptRoot/../.tools/inno/ISCC.exe",
    [string]$VcRuntime = 'C:/Program Files/Microsoft Visual Studio/2022/Community/VC/Redist/MSVC/14.44.35112/x64/Microsoft.VC143.CRT'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$versionLine = (Select-String -LiteralPath "$projectRoot/pubspec.yaml" -Pattern '^version:').Line
$buildVersion = ($versionLine -replace '^version:\s*', '').Trim()
$version = $buildVersion.Split('+')[0]
$release = Join-Path $projectRoot "artifacts/release/$version"
$windowsBuild = Join-Path $projectRoot 'build/windows/x64/runner/Release'
$stage = Join-Path $release 'windows'
if (!(Test-Path -LiteralPath "$windowsBuild/zero_player.exe")) { throw 'Build Windows release first.' }
if ((Get-Item -LiteralPath "$windowsBuild/zero_player.exe").VersionInfo.ProductVersion -ne $buildVersion) {
    throw 'Windows binary version does not match pubspec.yaml. Rebuild the release first.'
}
if (!(Test-Path -LiteralPath "$projectRoot/artifacts/notices/inventory.json")) { throw 'Run collect_notices.py first.' }
if (!(Test-Path -LiteralPath "$projectRoot/artifacts/native-sources/manifest.json")) { throw 'Run collect_native_sources.py first.' }
if (!(Test-Path -LiteralPath "$release/zero-player-$version-source.zip")) { throw 'Stage reviewed sources and run package_source.py first.' }
if (!(Test-Path -LiteralPath $VcRuntime)) { throw 'Specify the installed Visual C++ redistributable directory.' }
if (Test-Path -LiteralPath $stage) { throw 'Staging already exists. Inspect it before retrying.' }
$androidFiles = @{
    'app-release.apk' = "zero-player-$version-android-universal.apk"
    'app-arm64-v8a-release.apk' = "zero-player-$version-android-arm64.apk"
    'app-x86_64-release.apk' = "zero-player-$version-android-x64.apk"
}
$bundle = "$projectRoot/build/app/outputs/bundle/release/app-release.aab"
if (!$WindowsOnly) {
    foreach ($name in $androidFiles.Keys) {
        if (!(Test-Path -LiteralPath "$projectRoot/build/app/outputs/flutter-apk/$name")) { throw "Missing Android APK: $name" }
    }
    if (!(Test-Path -LiteralPath $bundle)) { throw 'Build Android appbundle first.' }
}
New-Item -ItemType Directory -Force $stage | Out-Null
Copy-Item -Path "$windowsBuild/*" -Destination $stage -Recurse
Copy-Item -Path "$VcRuntime/*.dll" -Destination $stage
Copy-Item -LiteralPath "$projectRoot/LICENSE","$projectRoot/NOTICE.md","$projectRoot/README.md" -Destination $stage
Copy-Item -LiteralPath "$projectRoot/artifacts/notices" -Destination "$stage/third-party-notices" -Recurse
$longPaths = @(Get-ChildItem -LiteralPath $stage -Recurse -File | Where-Object {
    $_.FullName.Substring($stage.Length + 1).Length -gt 160
})
if ($longPaths.Count -gt 0) {
    throw 'Package paths exceed 160 characters. Regenerate dependency notices with collect_notices.py before packaging.'
}
if (!$WindowsOnly) {
    foreach ($name in $androidFiles.Keys) {
        Copy-Item -LiteralPath "$projectRoot/build/app/outputs/flutter-apk/$name" -Destination (Join-Path $release $androidFiles[$name])
    }
    Copy-Item -LiteralPath $bundle -Destination "$release/zero-player-$version-android.aab"
}
Compress-Archive -Path "$stage/*" -DestinationPath "$release/zero-player-$version-windows-x64-portable.zip" -CompressionLevel Optimal
& $Iscc "/DProductVersion=$version" "/DReleaseRoot=$release" "$projectRoot/tool/windows.iss"
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup compilation failed.' }
Compress-Archive -Path "$projectRoot/artifacts/notices/*" -DestinationPath "$release/zero-player-$version-third-party-notices.zip" -CompressionLevel Optimal -Force
Compress-Archive -Path "$projectRoot/artifacts/native-sources/*" -DestinationPath "$release/zero-player-$version-native-sources.zip" -CompressionLevel Fastest -Force
Get-ChildItem -LiteralPath $release -File | Where-Object { $_.Extension -in '.apk','.aab','.zip','.exe' } | Sort-Object Name | ForEach-Object {
    $digest = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    "$digest  $($_.Name)"
} | Set-Content -LiteralPath "$release/SHA256SUMS.txt" -Encoding ascii
