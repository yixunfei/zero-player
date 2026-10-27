param([string]$PubCache = "$env:LOCALAPPDATA/Pub/Cache/hosted/pub.flutter-io.cn")
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$sqlite = @{
    'libsqlite3.arm64.android.so' = '0c2d3bfc8c87abceb21ed72a4bb49964121c5fe1a8ef3848d83ba907d01b6161'
    'libsqlite3.x64.android.so' = '949965f0eba976f707ae364cdcb42c342b5f0626081f8d7f0378fb7b52848772'
}
foreach ($entry in $sqlite.GetEnumerator()) {
    $folder = Join-Path $projectRoot ('.dart_tool/hooks_runner/shared/sqlite3/build/download-' + $entry.Value.Substring(0, 8))
    New-Item -ItemType Directory -Force $folder | Out-Null
    $target = Join-Path $folder 'libsqlite3.so'
    if (!(Test-Path -LiteralPath $target) -or (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.Value) {
        Invoke-WebRequest -Uri ('https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.5.2/' + $entry.Key) -OutFile $target -TimeoutSec 120
    }
    if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -ne $entry.Value) { throw 'SQLite checksum mismatch' }
    Write-Output "Verified $($entry.Key)"
}
$folder = Join-Path $projectRoot '.tools/ffmpegkit'
New-Item -ItemType Directory -Force $folder | Out-Null
$archive = Join-Path $folder 'windows-min.zip'
$hash = 'F1005A536A4440EB69CBBC2D610F12FCA4E45F039784285E405B0B5AB48AA6D6'
if (!(Test-Path -LiteralPath $archive) -or (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $hash) {
    Invoke-WebRequest -Uri 'https://github.com/sk3llo/ffmpeg_kit_flutter/releases/download/8.1.2-min/ffmpeg-kit-windows-x86_64-min-8.1.2.zip' -OutFile $archive -TimeoutSec 120
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $hash) { throw 'FFmpegKit checksum mismatch' }
Expand-Archive -LiteralPath $archive -DestinationPath (Join-Path $folder 'unpacked') -Force
Write-Output "Set FFMPEGKIT_LOCAL_DIR=$folder/unpacked for Windows builds."
