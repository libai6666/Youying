<#
# 查看当前版本，不修改
.\dev.cmd -Action version -ShowVersion

# 设置版本名，构建号自动加 1
.\dev.cmd -Action version -Version 0.2.0

# 或者只将构建号加 1
.\dev.cmd -Action version -BumpBuild

# 或者同时指定两者（构建号允许相同或回退，但会影响覆盖升级）
.\dev.cmd -Action version -Version 0.2.1 -BuildNumber 10

# debug调试mumu模拟器
.\dev.cmd -Action debug -Device 192.168.0.103:5555
#>
[CmdletBinding()]
param(
    [string]$Version,
    [ValidateRange(1,2100000000)][long]$BuildNumber,
    [switch]$BumpBuild,
    [switch]$ShowVersion,
    [switch]$NonInteractive
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$path = Join-Path (Split-Path $PSScriptRoot -Parent) 'pubspec.yaml'
$hasVersion = $PSBoundParameters.ContainsKey('Version')
$hasBuild = $PSBoundParameters.ContainsKey('BuildNumber')
if ($ShowVersion -and ($hasVersion -or $hasBuild -or $BumpBuild)) { throw 'ShowVersion cannot be combined with changes.' }
if ($BumpBuild -and $hasBuild) { throw 'Use either BumpBuild or BuildNumber, not both.' }

$original = [IO.File]::ReadAllBytes($path)
$hasBom = $original.Length -ge 3 -and $original[0] -eq 239 -and $original[1] -eq 187 -and $original[2] -eq 191
$offset = if ($hasBom) { 3 } else { 0 }
$encoding = New-Object Text.UTF8Encoding($false,$true)
$content = $encoding.GetString($original,$offset,$original.Length - $offset)
$lines = [regex]::Matches($content,'(?m)^version[ \t]*:[^\r\n]*')
if ($lines.Count -ne 1) { throw 'Expected exactly one top-level version field in pubspec.yaml.' }
$namePattern = '(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)'
$valuePattern = '^(?<prefix>version[ \t]*:[ \t]+)(?<quote>[''\"]?)(?<name>' + $namePattern + ')\+(?<build>[1-9][0-9]*)\k<quote>(?<suffix>[ \t]+#[^\r\n]*|[ \t]*)$'
$value = [regex]::Match($lines[0].Value,$valuePattern)
if (-not $value.Success) { throw 'Current version must use X.Y.Z+N, for example 0.1.0+1.' }
$currentName = $value.Groups['name'].Value
$currentBuild = 0L
if (-not [long]::TryParse($value.Groups['build'].Value,[ref]$currentBuild) -or $currentBuild -gt 2100000000) {
    throw 'Current Android build number must be between 1 and 2100000000.'
}
Write-Host "Current version: $currentName+$currentBuild"
if ($ShowVersion) { return }
if (-not ($hasVersion -or $hasBuild -or $BumpBuild)) {
    if ($NonInteractive) { throw 'Specify Version, BuildNumber or BumpBuild; use ShowVersion to view only.' }
    $Version = Read-Host '新版本名（如 0.2.0，回车保留当前版本名）'
    $hasVersion = -not [string]::IsNullOrWhiteSpace($Version)
    $inputBuild = Read-Host '新 Android 构建号（回车将当前构建号加 1）'
    if (-not [string]::IsNullOrWhiteSpace($inputBuild)) {
        if (-not [long]::TryParse($inputBuild,[ref]$BuildNumber)) { throw 'Build number must be an integer.' }
        $hasBuild = $true
    }
}
$nextName = if ($hasVersion) { $Version.Trim() } else { $currentName }
if ($nextName -notmatch ('\A' + $namePattern + '\z')) { throw 'Version name must use X.Y.Z with no leading zeros, for example 0.2.0.' }
$nextBuild = if ($hasBuild) { $BuildNumber } else { $currentBuild + 1 }
if ($nextBuild -gt 2100000000) {
    throw 'New Android build number must be at most 2100000000.'
}
if ($nextBuild -le $currentBuild) {
    Write-Warning "Build number $nextBuild does not exceed the current $currentBuild. Android treats it as not newer, so it cannot install over devices already on $currentBuild or above."
}
$nextValue = "$nextName+$nextBuild"
$replacement = $value.Groups['prefix'].Value + $value.Groups['quote'].Value + $nextValue + $value.Groups['quote'].Value + $value.Groups['suffix'].Value
$updated = $content.Substring(0,$lines[0].Index) + $replacement + $content.Substring($lines[0].Index + $lines[0].Length)
$updatedBytes = $encoding.GetBytes($updated)
if ($hasBom) { $updatedBytes = [byte[]](@(239,187,191) + $updatedBytes) }
$temporary = Join-Path (Split-Path $path -Parent) ('.pubspec-version-' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
    [IO.File]::WriteAllBytes($temporary,$updatedBytes)
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -ne [Convert]::ToBase64String($original)) {
        throw 'pubspec.yaml changed while editing the version; no update was applied. Retry after saving your editor.'
    }
    [IO.File]::Replace($temporary,$path,[NullString]::Value)
}
finally { if (Test-Path -LiteralPath $temporary) { Remove-Item -LiteralPath $temporary } }
Write-Host "Updated version: $currentName+$currentBuild -> $nextValue"
Write-Host 'Only pubspec.yaml changed. No APK was built; signing keys were not changed.'
