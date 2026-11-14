$ErrorActionPreference = 'Stop'
$file = Join-Path $PSScriptRoot '../workerhub.cmd'
$bytes = [IO.File]::ReadAllBytes($file)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) {
    throw 'CMD must not have a UTF-8 BOM.'
}
$source = [Text.Encoding]::UTF8.GetString($bytes)
if ($source -match '(?<!\r)\n') { throw 'CMD requires CRLF line endings.' }
$parts = $source -split '(?m)^# POWERSHELL START\r?$', 2
if ($parts.Count -ne 2) { throw 'Embedded PowerShell marker missing.' }
$tokens = $null
$parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseInput($parts[1], [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
. ([scriptblock]::Create($parts[1])) -LibraryOnly

# Library mode must never enter the menu, access the network or write real settings.
function Get-Json { throw 'Network is not allowed in smoke tests.' }
function Set-UserVariable { throw 'User environment writes are not allowed in smoke tests.' }
function Choose { throw 'Interactive UI is not allowed in smoke tests.' }

$header = @(Get-TomlTablePath '[projects.''c:\users\sample\project.with.dots''] # comment')
if ($header.Count -ne 2 -or $header[1] -cne 'c:\users\sample\project.with.dots') { throw 'Quoted project path regression.' }
$plugin = @(Get-TomlTablePath '[plugins."codex-app-tools@openai-bundled"]')
if ($plugin.Count -ne 2 -or $plugin[1] -cne 'codex-app-tools@openai-bundled') { throw 'Quoted plugin regression.' }
$array = @(Get-TomlTablePath '[[custom."table.name"]]')
if ($array.Count -ne 2 -or $array[1] -cne 'table.name') { throw 'Array-table regression.' }
$original = @'
model = "previous-model"
model_provider = "previous"
approval_policy = "on-request"
[projects.'c:\users\sample\project.with.dots']
trust_level = "trusted"
[plugins."codex-app-tools@openai-bundled"]
enabled = true
[model_providers.previous]
name = "Keep me"
base_url = "https://example.invalid/v1"
'@
$updated = Update-Codex $original 'example-model' 'C:\sample\workerhub-models.json'
foreach ($preserved in @('approval_policy = "on-request"', '[projects.''c:\users\sample\project.with.dots'']', 'trust_level = "trusted"', '[plugins."codex-app-tools@openai-bundled"]', 'enabled = true', '[model_providers.previous]', 'name = "Keep me"')) {
    if (-not $updated.Contains($preserved)) { throw "Lost unrelated setting: $preserved" }
}
if (-not $updated.Contains('model = "example-model"') -or -not $updated.Contains('env_key = "WORKERHUB_API_KEY"')) { throw 'Provider/model update failed.' }
$again = Update-Codex $updated 'example-model' 'C:\sample\workerhub-models.json'
if ($updated -cne $again) { throw 'Repeated configuration must be idempotent.' }
$refused = $false
try { [void](Update-Codex 'model_providers = { other = {} }' 'example-model' 'catalog.json') }
catch { $refused = $true }
if (-not $refused) { throw 'Unsafe inline provider syntax must be refused.' }
Write-Output 'PASS: PS syntax, encoding, quoted TOML tables, preserved settings, repeat runs and unsupported syntax.'
