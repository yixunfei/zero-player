# Optional workaround for Java/CMake downloads not using the host's proxy.
# Versions and upstream checksums match the locked media_kit native packages.
param([ValidateSet('android', 'windows')][string]$Platform = 'android')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$items = if ($Platform -eq 'android') {
    @(
        @('default-arm64-v8a.jar', '83df25b61193af8fa815e373143ac9af'),
        @('default-armeabi-v7a.jar', '22e21526fefc0a2b8f17adbec9f57590'),
        @('default-x86_64.jar', '6fa26bf0459b11f1c0b0dbc29e5b940d'),
        @('default-x86.jar', '0d742b756dc9d1fcd84ea271d8b68f32')
    ) | ForEach-Object { [PSCustomObject]@{
        Name = $_[0]; MD5 = $_[1]
        URL = "https://github.com/media-kit/libmpv-android-video-build/releases/download/v1.1.7/$($_[0])"
        Folder = 'build/media_kit_libs_android_video/v1.1.7'
    }}
} else {
    @(
        [PSCustomObject]@{Name='mpv-dev-x86_64-20230924-git-652a1dd.7z'; MD5='a832ef24b3a6ff97cd2560b5b9d04cd8'; Folder='build/windows/x64'; URL='https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z'},
        [PSCustomObject]@{Name='ANGLE.7z'; MD5='e866f13e8d552348058afaafe869b1ed'; Folder='build/windows/x64'; URL='https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z'}
    )
}
foreach ($item in $items) {
    $folder = Join-Path $projectRoot $item.Folder
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $target = Join-Path $folder $item.Name
    if ((Test-Path -LiteralPath $target) -and (Get-FileHash -LiteralPath $target -Algorithm MD5).Hash -eq $item.MD5) {
        Write-Output "Verified cached $($item.Name)"
        continue
    }
    Write-Output "Downloading $($item.Name)"
    Invoke-WebRequest -Uri $item.URL -OutFile "$target.partial" -TimeoutSec 180
    if ((Get-FileHash -LiteralPath "$target.partial" -Algorithm MD5).Hash -ne $item.MD5) {
        throw "Upstream checksum mismatch for $($item.Name)"
    }
    Move-Item -LiteralPath "$target.partial" -Destination $target -Force
    Get-FileHash -LiteralPath $target -Algorithm SHA256 | Select-Object Path,Hash
}
