[CmdletBinding()]
param(
    [ValidateSet('menu','doctor','check','debug','test','release','git')][string]$Action = 'menu',
    [string]$Device,
    [ValidateSet('android-arm64','android-arm','android-x64','android-arm,android-arm64,android-x64')]
    [string]$TargetPlatform = 'android-arm,android-arm64,android-x64',
    [switch]$NonInteractive
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Root = Split-Path $PSScriptRoot -Parent

function Invoke-Tool([string]$Name, [string[]]$Arguments) {
    $command = Get-Command $Name -ErrorAction Stop
    & $command.Source @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Name failed (exit $LASTEXITCODE)" }
}

function Find-Adb {
    $found = Get-Command adb -ErrorAction SilentlyContinue
    if ($found) { return $found.Source }
    $sdkPaths = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
    if ($env:LOCALAPPDATA) { $sdkPaths += (Join-Path $env:LOCALAPPDATA 'Android\Sdk') }
    foreach ($sdk in $sdkPaths) {
        if (-not $sdk) { continue }
        foreach ($name in @('adb.exe','adb')) {
            $candidate = Join-Path $sdk "platform-tools/$name"
            if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
        }
    }
    throw 'ADB missing. Install Android SDK Platform-Tools; set ANDROID_HOME or add platform-tools to PATH.'
}

function Request-Secret([string]$Prompt) {
    $secure = Read-Host $Prompt -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose() }
}

function Find-ApkSigner {
    foreach ($name in @('apksigner','apksigner.bat')) {
        $found = Get-Command $name -ErrorAction SilentlyContinue
        if ($found) { return $found.Source }
    }
    $sdkPaths = @($env:ANDROID_SDK_ROOT, $env:ANDROID_HOME)
    if ($env:LOCALAPPDATA) { $sdkPaths += (Join-Path $env:LOCALAPPDATA 'Android\Sdk') }
    foreach ($sdk in $sdkPaths) {
        if (-not $sdk) { continue }
        $directory = Join-Path $sdk 'build-tools'
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { continue }
        foreach ($version in (Get-ChildItem -LiteralPath $directory -Directory | Sort-Object Name -Descending)) {
            foreach ($name in @('apksigner.bat','apksigner')) {
                $candidate = Join-Path $version.FullName $name
                if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
            }
        }
    }
    throw 'apksigner missing. Install Android SDK Build-Tools and set ANDROID_HOME.'
}

function Build-Release {
    $keys = @('YOUYING_KEYSTORE','YOUYING_KEY_ALIAS','YOUYING_STORE_PASSWORD','YOUYING_KEY_PASSWORD')
    $saved = @{}
    foreach ($key in $keys) { $saved[$key] = [Environment]::GetEnvironmentVariable($key,'Process') }
    try {
        foreach ($key in $keys) {
            if ([Environment]::GetEnvironmentVariable($key,'Process')) { continue }
            if ($NonInteractive) { throw "Release signing is missing $key" }
            $value = if ($key.EndsWith('PASSWORD')) { Request-Secret $key } else { Read-Host $key }
            if ([string]::IsNullOrWhiteSpace($value)) { throw "Release signing is missing $key" }
            [Environment]::SetEnvironmentVariable($key,$value,'Process')
        }
        if (-not (Test-Path -LiteralPath $env:YOUYING_KEYSTORE -PathType Leaf)) { throw 'Keystore not found' }
        $env:YOUYING_KEYSTORE = (Resolve-Path -LiteralPath $env:YOUYING_KEYSTORE).Path
        Invoke-Tool 'flutter' @('build','apk','--release','--target-platform',$TargetPlatform)
    }
    finally {
        foreach ($key in $keys) { [Environment]::SetEnvironmentVariable($key,$saved[$key],'Process') }
    }
}

function Copy-Apk([string]$Mode, [string]$Kind) {
    $apk = Join-Path $Root "build/app/outputs/flutter-apk/app-$Mode.apk"
    if (-not (Test-Path -LiteralPath $apk -PathType Leaf)) { throw 'APK was not produced' }
    if ($Kind -eq 'release') { Invoke-Tool (Find-ApkSigner) @('verify','--verbose',$apk) }
    $directory = Join-Path $Root "dist/$Kind"
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $destination = Join-Path $directory ("youying-$Kind-" + (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '.apk')
    if (Test-Path -LiteralPath $destination) { throw 'Refusing to overwrite an existing APK' }
    Copy-Item -LiteralPath $apk -Destination $destination
    Write-Host "APK: $destination"
    Write-Host ('SHA-256: ' + (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash)
}

Push-Location $Root
try {
    if ($Action -eq 'menu') {
        Write-Host 'Youying / 柚影'
        Write-Host '1 环境检查  2 分析与测试  3 USB 手机调试  4 测试包  5 正式签名包  6 Git 初始化/状态  0 退出'
        $choices = @{'1'='doctor';'2'='check';'3'='debug';'4'='test';'5'='release';'6'='git';'0'='exit'}
        $answer = Read-Host '请选择'
        if (-not $choices.ContainsKey($answer)) { throw 'Invalid menu selection' }
        if ($choices[$answer] -eq 'exit') { exit 0 }
        $Action = $choices[$answer]
    }
    switch ($Action) {
        'doctor' { Invoke-Tool 'flutter' @('doctor','-v'); $adb = Find-Adb; Invoke-Tool $adb @('devices','-l') }
        'check' { Invoke-Tool 'flutter' @('pub','get'); Invoke-Tool 'flutter' @('analyze'); Invoke-Tool 'flutter' @('test') }
        'debug' {
            Invoke-Tool 'flutter' @('pub','get')
            $adb = Find-Adb
            Invoke-Tool $adb @('devices','-l')
            if (-not $Device) {
                $serial = & $adb '-d' 'get-serialno'
                if ($LASTEXITCODE -ne 0 -or -not $serial -or $serial -eq 'unknown') {
                    throw 'No unique USB device. Check phone authorization or specify -Device SERIAL.'
                }
                $Device = ($serial | Select-Object -Last 1).Trim()
            }
            $state = & $adb '-s' $Device 'get-state'
            if ($LASTEXITCODE -ne 0 -or ($state | Select-Object -Last 1) -ne 'device') { throw 'Device is offline or unauthorized' }
            Invoke-Tool 'flutter' @('run','--debug','-d',$Device)
        }
        'test' {
            Invoke-Tool 'flutter' @('pub','get')
            Invoke-Tool 'flutter' @('build','apk','--debug','--target-platform',$TargetPlatform)
            Copy-Apk 'debug' 'test'
        }
        'release' {
            if ($NonInteractive) {
                foreach ($key in @('YOUYING_KEYSTORE','YOUYING_KEY_ALIAS','YOUYING_STORE_PASSWORD','YOUYING_KEY_PASSWORD')) {
                    if (-not [Environment]::GetEnvironmentVariable($key,'Process')) { throw "Release signing is missing $key" }
                }
            }
            Invoke-Tool 'flutter' @('pub','get')
            Invoke-Tool 'flutter' @('analyze')
            Invoke-Tool 'flutter' @('test')
            Build-Release
            Copy-Apk 'release' 'release'
        }
        'git' {
            if (-not (Test-Path -LiteralPath (Join-Path $Root '.git'))) { Invoke-Tool 'git' @('init','--initial-branch=main') }
            Invoke-Tool 'git' @('status','--short','--branch')
        }
    }
}
catch { Write-Error $_ -ErrorAction Continue; exit 1 }
finally { Pop-Location }
