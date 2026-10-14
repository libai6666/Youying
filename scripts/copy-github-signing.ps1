[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT') { throw 'Run this helper under the original Windows signing account.' }
Get-Command Set-Clipboard -ErrorAction Stop | Out-Null
$configuration = Join-Path $HOME 'AndroidKeys/youying/signing.clixml'
if (-not (Test-Path -LiteralPath $configuration -PathType Leaf)) {
    throw 'Local signing configuration missing. Restore the original key; do not create a replacement.'
}

function Read-SigningSecret([string]$Name, [object]$Signing) {
    switch ($Name) {
        'YOUYING_KEYSTORE_BASE64' {
            $bytes = [IO.File]::ReadAllBytes($Signing.StoreFile)
            try { return [Convert]::ToBase64String($bytes) }
            finally { [Array]::Clear($bytes,0,$bytes.Length) }
        }
        'YOUYING_KEY_ALIAS' { return $Signing.KeyAlias }
        default {
            $secure = if ($Name -eq 'YOUYING_STORE_PASSWORD') { $Signing.StorePassword } else { $Signing.KeyPassword }
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
        }
    }
}

$signing = $null
$clipboardTouched = $false
try {
    $signing = Import-Clixml -LiteralPath $configuration
    if ($signing.StorePassword -isnot [Security.SecureString] -or $signing.KeyPassword -isnot [Security.SecureString]) {
        throw 'Cannot unlock signing configuration. Use the original Windows account.'
    }
    if (-not [IO.Path]::IsPathRooted($signing.StoreFile) -or -not (Test-Path -LiteralPath $signing.StoreFile -PathType Leaf)) {
        throw 'Original release keystore missing. Restore your backup; do not regenerate it.'
    }
    if ([string]::IsNullOrWhiteSpace($signing.KeyAlias)) { throw 'Signing alias missing.' }
    if ((Get-Item -LiteralPath $signing.StoreFile).Length -gt 36000) { throw 'Keystore is too large for a GitHub secret.' }
    Write-Host '在 GitHub 仓库打开 Settings > Secrets and variables > Actions > New repository secret。'
    Write-Warning '剪贴板将短暂保存私钥或密码。请先关闭剪贴板历史、云同步和剪贴板管理器；不要截图、分享或粘贴到聊天。'
    if ((Read-Host '确认已准备好？输入 YES 继续，其他输入取消') -cne 'YES') {
        Write-Host '已取消，没有复制或上传任何密钥。'
        return
    }
    foreach ($name in @('YOUYING_KEYSTORE_BASE64','YOUYING_KEY_ALIAS','YOUYING_STORE_PASSWORD','YOUYING_KEY_PASSWORD')) {
        Write-Host "Secret Name: $name"
        Read-Host '先在网页填好上面的 Name，再回车复制对应的值' | Out-Null
        $value = Read-SigningSecret $name $signing
        try {
            $clipboardTouched = $true
            Set-Clipboard -Value $value
        }
        finally { $value = $null }
        Read-Host '在网页 Secret 框中粘贴并点击 Add secret；完成后回车继续' | Out-Null
        Set-Clipboard -Value ''
    }
    Write-Host '四项值已逐项复制。请确认 GitHub 页面已保存四项 Secrets，再运行 Actions。'
    Write-Host '没有生成新密钥，没有写入秘密文件，也没有自动上传任何内容。'
}
finally {
    if ($clipboardTouched) {
        try { Set-Clipboard -Value '' }
        catch { Write-Warning '无法清空剪贴板，请手动清空。' }
    }
    if ($null -ne $signing) {
        foreach ($property in @('StorePassword','KeyPassword')) {
            $entry = $signing.PSObject.Properties[$property]
            if ($null -ne $entry -and $entry.Value -is [Security.SecureString]) { $entry.Value.Dispose() }
        }
    }
}
