[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$source = Join-Path $PSScriptRoot 'set-version.ps1'
$project = Join-Path (Split-Path $PSScriptRoot -Parent) 'pubspec.yaml'
$original = [IO.File]::ReadAllBytes($project)
$directory = Join-Path ([IO.Path]::GetTempPath()) ('youying-version-tests-' + [guid]::NewGuid().ToString('N'))
$encoding = New-Object Text.UTF8Encoding($false)
$script:count = 0

function Test-Version([string]$Name, [hashtable]$Arguments, [string]$Before, [string]$After, [bool]$ShouldFail = $false, [bool]$Bom = $false) {
    $script:count++
    $fixture = Join-Path $directory $script:count
    $scripts = Join-Path $fixture 'scripts'
    New-Item -ItemType Directory -Force -Path $scripts | Out-Null
    Copy-Item -LiteralPath $source -Destination (Join-Path $scripts 'set-version.ps1')
    $path = Join-Path $fixture 'pubspec.yaml'
    $beforeBytes = $encoding.GetBytes($Before)
    $expectedBytes = $encoding.GetBytes($After)
    if ($Bom) {
        $beforeBytes = [byte[]](@(239,187,191) + $beforeBytes)
        $expectedBytes = [byte[]](@(239,187,191) + $expectedBytes)
    }
    [IO.File]::WriteAllBytes($path,$beforeBytes)
    $failed = $false
    try { & (Join-Path $scripts 'set-version.ps1') @Arguments -NonInteractive }
    catch { $failed = $true }
    if ($failed -ne $ShouldFail) { throw "Unexpected result: $Name" }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($path)) -cne [Convert]::ToBase64String($expectedBytes)) {
        throw "Unexpected bytes: $Name"
    }
    if (@(Get-ChildItem -LiteralPath $fixture -Filter '.pubspec-version-*.tmp').Count) { throw "Temporary file leaked: $Name" }
    Write-Host "PASS $Name"
}

try {
    $simple = "name: fixture`nversion: 0.1.0+1`n"
    $quoted = "version : '0.1.0+1' # keep`r`nname: fixture`r`nextra:`r`n  version: unchanged`r`n"
    Test-Version 'manual bump preserves BOM CRLF quotes and comments' @{BumpBuild=$true} $quoted ($quoted.Replace('0.1.0+1','0.1.0+2')) $false $true
    Test-Version 'show preserves BOM CRLF quotes and comments' @{ShowVersion=$true} $quoted $quoted $false $true
    Test-Version 'manual upper bound' @{BumpBuild=$true} 'version: 0.1.0+2099999999' 'version: 0.1.0+2100000000'
    Test-Version 'manual overflow rejected' @{BumpBuild=$true} 'version: 0.1.0+2100000000' 'version: 0.1.0+2100000000' $true
    foreach ($build in @(0L,-1L,2100000001L)) {
        Test-Version "invalid manual build $build" @{BuildNumber=$build} $simple $simple $true
    }
    foreach ($name in @('0.2','01.2.0','0.2.0-beta.1')) {
        Test-Version "invalid version name $name" @{Version=$name} $simple $simple $true
    }
    foreach ($arguments in @(@{ShowVersion=$true;Version='0.2.0'}, @{ShowVersion=$true;BuildNumber=3}, @{ShowVersion=$true;BumpBuild=$true}, @{BuildNumber=3;BumpBuild=$true})) {
        Test-Version 'conflicting options rejected' $arguments $simple $simple $true
    }
    foreach ($before in @("version: 0.1.0+1`nversion: 0.2.0+2`n", 'name: fixture', 'version: 0.1.0', 'version: 0.1.0+0', 'version: "0.1.0+1', 'version: 0.1.0+9999999999999999999999')) {
        Test-Version 'invalid source version rejected' @{ShowVersion=$true} $before $before $true
    }
    Test-Version 'manual bump unchanged' @{BumpBuild=$true} $simple ($simple.Replace('0.1.0+1','0.1.0+2'))
    Test-Version 'manual version name unchanged' @{Version='0.2.0'} $simple ($simple.Replace('0.1.0+1','0.2.0+2'))
    Test-Version 'manual explicit build unchanged' @{BuildNumber=10} $simple ($simple.Replace('0.1.0+1','0.1.0+10'))
    Test-Version 'show is read only' @{ShowVersion=$true} $simple $simple
    Test-Version 'repeated show keeps exact manual version' @{ShowVersion=$true} $simple $simple
    Test-Version 'manual explicit name and build' @{Version='0.3.0';BuildNumber=20} $simple ($simple.Replace('0.1.0+1','0.3.0+20'))
    Test-Version 'manual same build allowed' @{BuildNumber=1} $simple $simple
    Test-Version 'manual downgrade allowed' @{BuildNumber=2} "name: fixture`nversion: 0.1.0+5`n" "name: fixture`nversion: 0.1.0+2`n"
    Test-Version 'noninteractive missing change rejected' @{} $simple $simple $true
    Write-Host "VERSION_TESTS_PASSED $script:count cases"
}
finally {
    if (Test-Path -LiteralPath $directory) { Remove-Item -LiteralPath $directory -Recurse -Force }
    if ([Convert]::ToBase64String([IO.File]::ReadAllBytes($project)) -cne [Convert]::ToBase64String($original)) {
        throw 'Project pubspec.yaml changed during version tests.'
    }
}
