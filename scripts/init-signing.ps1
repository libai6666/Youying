[CmdletBinding()]
param([string]$Directory = (Join-Path $HOME 'AndroidKeys/youying'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$Directory = [IO.Path]::GetFullPath($Directory)
$project = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent)).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
if (($Directory.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar).StartsWith($project,[StringComparison]::OrdinalIgnoreCase)) {
    throw 'Signing keys must be stored outside the project directory.'
}
$configuration = Join-Path $Directory 'signing.clixml'
$keystore = Join-Path $Directory 'youying-release.jks'
$recovery = Join-Path $Directory 'RECOVERY-PRIVATE.txt'

if (Test-Path -LiteralPath $configuration) {
    if (-not (Test-Path -LiteralPath $keystore -PathType Leaf)) { throw 'Signing configuration exists but keystore is missing. Restore your backup; do not generate a replacement key.' }
    Write-Host "Signing already configured. Existing key preserved: $keystore"
    return
}
if ((Test-Path -LiteralPath $keystore) -or (Test-Path -LiteralPath $recovery)) {
    throw 'Existing key or recovery file found. Refusing to overwrite. Restore the signing configuration from your backup.'
}
$keytool = (Get-Command keytool -ErrorAction Stop).Source
New-Item -ItemType Directory -Force -Path $Directory | Out-Null
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
$acl = New-Object Security.AccessControl.DirectorySecurity
$acl.SetOwner($identity)
$acl.SetAccessRuleProtection($true,$false)
foreach ($sid in @($identity, (New-Object Security.Principal.SecurityIdentifier 'S-1-5-18'))) {
    $rule = New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl','ContainerInherit,ObjectInherit','None','Allow')
    $acl.AddAccessRule($rule)
}
Set-Acl -LiteralPath $Directory -AclObject $acl

$bytes = New-Object byte[] 32
$rng = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
$password = [Convert]::ToBase64String($bytes)
[Array]::Clear($bytes,0,$bytes.Length)
$savedPassword = $env:YOUYING_INIT_PASSWORD
try {
    $env:YOUYING_INIT_PASSWORD = $password
    @(
        'PRIVATE: do not upload, share, or commit this file.',
        'Back up this password separately from the keystore in encrypted/offline storage.',
        'Keystore: youying-release.jks',
        'Store type: JKS',
        'Alias: youying',
        ('Store password: ' + $password),
        ('Key password: ' + $password)
    ) | Set-Content -LiteralPath $recovery -Encoding UTF8
    & $keytool '-genkeypair' '-keystore' $keystore '-storetype' 'JKS' '-keyalg' 'RSA' '-keysize' '3072' '-sigalg' 'SHA256withRSA' '-validity' '10000' '-alias' 'youying' '-dname' 'CN=Youying Release, OU=Mobile, O=Youying' '-storepass:env' 'YOUYING_INIT_PASSWORD' '-keypass:env' 'YOUYING_INIT_PASSWORD' '-noprompt'
    if ($LASTEXITCODE -ne 0) { throw 'Key generation failed; existing files were retained for recovery.' }
    $secure = ConvertTo-SecureString $password -AsPlainText -Force
    try {
        [PSCustomObject]@{
            StoreFile = $keystore
            KeyAlias = 'youying'
            StorePassword = $secure
            KeyPassword = $secure
        } | Export-Clixml -LiteralPath $configuration -Encoding UTF8
    }
    finally { $secure.Dispose() }
    $certificate = Join-Path $Directory 'release-certificate.cer'
    & $keytool '-exportcert' '-keystore' $keystore '-alias' 'youying' '-storepass:env' 'YOUYING_INIT_PASSWORD' '-file' $certificate
    if ($LASTEXITCODE -ne 0) { throw 'Certificate export failed' }
    $cert = New-Object Security.Cryptography.X509Certificates.X509Certificate2($certificate)
    $hash = [Security.Cryptography.SHA256]::Create()
    try { $fingerprint = [BitConverter]::ToString($hash.ComputeHash($cert.RawData)).Replace('-','') }
    finally { $hash.Dispose(); $cert.Dispose() }
    $fingerprint | Set-Content -LiteralPath (Join-Path $Directory 'certificate-sha256.txt') -Encoding ASCII
    Write-Host "Signing key ready: $keystore"
    Write-Host "Certificate SHA-256: $fingerprint"
    Write-Host "Private recovery instructions: $recovery (do not share this file)"
    Write-Host 'Back up the key and password separately before distributing APKs. Never regenerate this key for updates.'
}
finally {
    $env:YOUYING_INIT_PASSWORD = $savedPassword
    $password = $null
}
