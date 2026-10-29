param([string]$VoiceName = 'Microsoft Huihui Desktop')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$output = Join-Path $root 'test_support/generated/content_filter/speech.wav'
New-Item -ItemType Directory -Force -Path (Split-Path $output) | Out-Null
$speaker = New-Object -ComObject SAPI.SpVoice
$stream = New-Object -ComObject SAPI.SpFileStream
$opened = $false
try {
    $voices = $speaker.GetVoices()
    $voice = $null
    for ($index = 0; $index -lt $voices.Count; $index++) {
        $candidate = $voices.Item($index)
        if ($candidate.GetDescription().StartsWith($VoiceName, [StringComparison]::OrdinalIgnoreCase)) {
            $voice = $candidate
            break
        }
    }
    if ($null -eq $voice) { throw "Chinese SAPI voice unavailable: $VoiceName" }
    $speaker.Voice = $voice
    $stream.Format.Type = 18 # SAFT16kHz16BitMono
    $stream.Open($output, 3)
    $opened = $true
    $speaker.AudioOutputStream = $stream
    [void]$speaker.Speak('欢迎来到澳门新葡京赌场，真人在线，注册送礼，立即充值下注。')
    Write-Output $output
} finally {
    if ($opened) { $stream.Close() }
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($speaker)
    [void][Runtime.InteropServices.Marshal]::FinalReleaseComObject($stream)
}
