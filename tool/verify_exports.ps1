param([Parameter(Mandatory = $true)][string]$FFmpeg)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$fixtureDirectory = Join-Path $projectRoot 'test_support/generated'
$exportDirectory = Join-Path $projectRoot 'artifacts/m0/exports'
New-Item -ItemType Directory -Force -Path $exportDirectory | Out-Null
$reports = @()
foreach ($kind in @('ts', 'fmp4', 'aes', 'ranges', 'separate')) {
    foreach ($format in @('mp4', 'ts')) {
        $inputFile = Join-Path $fixtureDirectory "$kind/index.m3u8"
        $outputFile = Join-Path $exportDirectory "$kind.$format"
        $muxer = if ($format -eq 'ts') { 'mpegts' } else { 'mp4' }
        & $FFmpeg '-hide_banner' '-loglevel' 'error' '-y' '-allowed_extensions' 'ALL' '-i' $inputFile '-map' '0:v:0' '-map' '0:a:0' '-c' 'copy' '-f' $muxer $outputFile
        $remuxExit = $LASTEXITCODE
        $decodeExit = $null
        if ($remuxExit -eq 0) {
            & $FFmpeg '-hide_banner' '-loglevel' 'error' '-i' $outputFile '-map' '0:v:0' '-map' '0:a:0' '-f' 'null' '-'
            $decodeExit = $LASTEXITCODE
        }
        $reports += [PSCustomObject]@{
            input = $kind
            output = $format
            remuxExitCode = $remuxExit
            fullDecodeExitCode = $decodeExit
            passed = ($remuxExit -eq 0 -and $decodeExit -eq 0)
            bytes = if (Test-Path -LiteralPath $outputFile) { (Get-Item -LiteralPath $outputFile).Length } else { 0 }
            sha256 = if (Test-Path -LiteralPath $outputFile) { (Get-FileHash -LiteralPath $outputFile -Algorithm SHA256).Hash } else { $null }
        }
    }
}
$reports | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $exportDirectory 'results.json')
$reports | Format-Table input,output,passed,bytes
if (@($reports | Where-Object { -not $_.passed }).Count -gt 0) { exit 1 }
