# Run each native test in isolation, preserving caller environment and logs.
param(
    [Parameter(Mandatory = $true)][string[]]$TestFiles,
    [string[]]$DartDefines = @()
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$nativeDir = Join-Path $projectRoot '.tools/ffmpegkit/unpacked'
if (!(Test-Path -LiteralPath (Join-Path $nativeDir 'bin'))) {
    throw 'Missing verified FFmpegKit distribution: .tools/ffmpegkit/unpacked/bin'
}
$targets = foreach ($file in $TestFiles) {
    $target = (Resolve-Path -LiteralPath (Join-Path $projectRoot $file)).Path
    $allowedRoot = (Join-Path $projectRoot 'integration_test') + [IO.Path]::DirectorySeparatorChar
    if (!$target.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase) -or
        !$target.EndsWith('_test.dart')) {
        throw "Expected an integration_test/*_test.dart file: $file"
    }
    $target
}
$previousTemp = $env:TEMP
$previousTmp = $env:TMP
$previousNative = $env:FFMPEGKIT_LOCAL_DIR
$runRoot = Join-Path $projectRoot ('.dart_tool/native-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $runRoot | Out-Null
Push-Location $projectRoot
try {
    $env:FFMPEGKIT_LOCAL_DIR = $nativeDir
    $index = 0
    foreach ($target in $targets) {
        $testTemp = Join-Path $runRoot ([string]$index++)
        New-Item -ItemType Directory -Path $testTemp | Out-Null
        $env:TEMP = $testTemp
        $env:TMP = $testTemp
        $log = Join-Path $runRoot ([IO.Path]::GetFileNameWithoutExtension($target) + '.log')
        Write-Output "Running $target; log: $log"
        $defineArguments = @($DartDefines | ForEach-Object { "--dart-define=$_" })
        & flutter drive --driver=test_support/integration_driver.dart "--target=$target" -d windows --no-pub "--dart-define=PROJECT_ROOT=$projectRoot" @defineArguments *> $log
        $code = $LASTEXITCODE
        Get-Content -LiteralPath $log -Tail 20
        if ($code -ne 0) { throw "Native test failed (exit $code): $log" }
    }
} finally {
    $env:TEMP = $previousTemp
    $env:TMP = $previousTmp
    $env:FFMPEGKIT_LOCAL_DIR = $previousNative
    Pop-Location
}
