param([Parameter(Mandatory = $true)][string]$FFmpeg)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$outputDirectory = Join-Path $projectRoot 'test_support/generated'
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

function Invoke-MediaTool([string[]]$Arguments) {
    & $FFmpeg @Arguments
    if ($LASTEXITCODE -ne 0) { throw "FFmpeg failed with exit code $LASTEXITCODE" }
}

$sample = Join-Path $outputDirectory 'sample.mp4'
Invoke-MediaTool @('-hide_banner', '-loglevel', 'error', '-y',
    '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=44100',
    '-t', '12', '-c:a', 'pcm_s16le', (Join-Path $outputDirectory 'radio.wav'))
Invoke-MediaTool @('-hide_banner', '-loglevel', 'error', '-y',
    '-f', 'lavfi', '-i', 'testsrc2=size=640x360:rate=25',
    '-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000',
    '-t', '12', '-c:v', 'libx264', '-preset', 'ultrafast', '-pix_fmt', 'yuv420p',
    '-g', '50', '-keyint_min', '50', '-sc_threshold', '0',
    '-c:a', 'aac', '-b:a', '96k', '-movflags', '+faststart', $sample)

Invoke-MediaTool @('-hide_banner', '-loglevel', 'error', '-y', '-i', $sample, '-frames:v', '1', (Join-Path $outputDirectory 'poster.png'))

foreach ($kind in @('ts', 'fmp4')) {
    $folder = Join-Path $outputDirectory $kind
    New-Item -ItemType Directory -Force -Path $folder | Out-Null
    $extension = if ($kind -eq 'ts') { 'ts' } else { 'm4s' }
    $segmentType = if ($kind -eq 'ts') { 'mpegts' } else { 'fmp4' }
    Push-Location -LiteralPath $folder
    try {
        Invoke-MediaTool @('-hide_banner', '-loglevel', 'error', '-y', '-i', $sample,
            '-c', 'copy', '-hls_time', '2', '-hls_playlist_type', 'vod',
            '-hls_segment_type', $segmentType, '-hls_segment_filename',
            "segment-%03d.$extension", 'index.m3u8')
    } finally { Pop-Location }
}

$encrypted = Join-Path $outputDirectory 'aes'
New-Item -ItemType Directory -Force -Path $encrypted | Out-Null
$key = [byte[]](0..15)
$keyFile = Join-Path $encrypted 'key.bin'
[IO.File]::WriteAllBytes($keyFile, $key)
$keyInfo = Join-Path $encrypted 'key-info.txt'
[IO.File]::WriteAllText($keyInfo, "key.bin`n$keyFile`n000102030405060708090a0b0c0d0e0f`n")
Invoke-MediaTool @('-hide_banner', '-loglevel', 'error', '-y', '-i', $sample,
    '-c', 'copy', '-hls_time', '2', '-hls_playlist_type', 'vod',
    '-hls_key_info_file', $keyInfo, '-hls_segment_filename',
    (Join-Path $encrypted 'segment-%03d.ts'), (Join-Path $encrypted 'index.m3u8'))

Invoke-MediaTool @('-hide_banner', '-loglevel', 'error', '-y', '-i', $sample,
    '-c', 'copy', '-f', 'flv', (Join-Path $outputDirectory 'sample.flv'))
$ranges = Join-Path $outputDirectory 'ranges'
New-Item -ItemType Directory -Force -Path $ranges | Out-Null
Invoke-MediaTool @('-hide_banner', '-loglevel', 'error', '-y', '-i', $sample,
    '-c', 'copy', '-hls_time', '2', '-hls_playlist_type', 'vod',
    '-hls_flags', 'single_file', (Join-Path $ranges 'index.m3u8'))

$separate = Join-Path $outputDirectory 'separate'
New-Item -ItemType Directory -Force -Path $separate | Out-Null
Invoke-MediaTool @('-hide_banner', '-loglevel', 'error', '-y', '-i', $sample,
    '-an', '-c:v', 'copy', '-hls_time', '2', '-hls_playlist_type', 'vod',
    '-hls_segment_filename', (Join-Path $separate 'video-%03d.ts'),
    (Join-Path $separate 'video.m3u8'))
Invoke-MediaTool @('-hide_banner', '-loglevel', 'error', '-y', '-i', $sample,
    '-vn', '-c:a', 'copy', '-hls_time', '2', '-hls_playlist_type', 'vod',
    '-hls_segment_filename', (Join-Path $separate 'audio-%03d.ts'),
    (Join-Path $separate 'audio.m3u8'))
[IO.File]::WriteAllText((Join-Path $separate 'index.m3u8'),
    "#EXTM3U`n#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=`"audio`",NAME=`"Tone`",DEFAULT=YES,AUTOSELECT=YES,URI=`"audio.m3u8`"`n#EXT-X-STREAM-INF:BANDWIDTH=1600000,RESOLUTION=640x360,AUDIO=`"audio`"`nvideo.m3u8`n")
[IO.File]::WriteAllText((Join-Path $outputDirectory 'master.m3u8'),
    "#EXTM3U`n#EXT-X-STREAM-INF:BANDWIDTH=1600000,RESOLUTION=640x360`nts/index.m3u8`n")
Get-ChildItem -LiteralPath $outputDirectory -Recurse -File |
    Where-Object Name -ne 'key-info.txt' |
    Get-FileHash -Algorithm SHA256 |
    Select-Object Path,Hash | ConvertTo-Json |
    Set-Content -LiteralPath (Join-Path $outputDirectory 'sha256.json')
Write-Output "Generated synthetic H.264/AAC fixtures in $outputDirectory"
