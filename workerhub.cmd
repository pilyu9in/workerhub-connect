@echo off
setlocal
chcp 65001 >nul
set "WORKERHUB_SETUP_FILE=%~f0"
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -Command "$source=[IO.File]::ReadAllText($env:WORKERHUB_SETUP_FILE); $parts=$source -split '(?m)^# POWERSHELL START\r?$',2; & ([scriptblock]::Create($parts[1]))"
set "workerhub_result=%errorlevel%"
echo.
pause
exit /b %workerhub_result%
# POWERSHELL START
[CmdletBinding()]
param([switch]$LibraryOnly)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$script:Language = 'en'
$script:Utf8 = New-Object Text.UTF8Encoding($false)
$script:ApiBase = 'https://workerhub.cc/worker-api/v1'
$script:ClaudeBase = 'https://workerhub.cc/worker-api'
$script:DesktopProfileId = '8d8eea95-a59c-4c2a-8671-776f726b6572'

function Text([string]$Ru, [string]$En) {
    if ($script:Language -eq 'ru') { return $Ru }
    return $En
}

function Choose([string]$Title, [string[]]$Options) {
    if (-not $Options.Count) { throw 'No options available.' }
    Write-Host "`n$Title"
    $selected = 0
    $rows = [Math]::Min(7, $Options.Count)
    for ($row = 0; $row -lt $rows; $row++) { Write-Host '' }
    $top = [Console]::CursorTop - $rows
    $cursor = [Console]::CursorVisible
    $controlC = [Console]::TreatControlCAsInput
    try {
        [Console]::CursorVisible = $false
        [Console]::TreatControlCAsInput = $true
        while ($true) {
            $first = [Math]::Max(0, [Math]::Min($selected - $rows + 1, $Options.Count - $rows))
            [Console]::SetCursorPosition(0, $top)
            $width = [Math]::Max(8, [Console]::WindowWidth - 2)
            for ($row = 0; $row -lt $rows; $row++) {
                $index = $first + $row
                $marker = ' '
                if ($index -eq $selected) { $marker = '>' }
                $line = " $marker $($Options[$index])"
                if ($line.Length -gt $width) { $line = $line.Substring(0, $width - 3) + '...' }
                Write-Host ($line.PadRight($width))
            }
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq 'Escape' -or ($key.Key -eq 'C' -and ($key.Modifiers -band [ConsoleModifiers]::Control))) {
                throw [OperationCanceledException]::new('Cancelled.')
            }
            switch ($key.Key) {
                'UpArrow' { $selected = ($selected + $Options.Count - 1) % $Options.Count }
                'DownArrow' { $selected = ($selected + 1) % $Options.Count }
                'Enter' { return $selected }
            }
        }
    } finally {
        [Console]::CursorVisible = $cursor
        [Console]::TreatControlCAsInput = $controlC
    }
}

function Get-Json([string]$Url) {
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 25 -MaximumRedirection 0
        if ($response.Content.Length -gt 8000000) { throw 'Response too large.' }
        return ($response.Content | ConvertFrom-Json)
    } catch {
        throw (Text "Не удалось загрузить каталог: $Url" "Could not load catalog: $Url")
    }
}

function Set-Value($Object, [string]$Name, $Value) {
    $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value -Force
}

function Get-Catalog($Live, $Official) {
    $result = @()
    foreach ($id in $Live) {
        $entry = @($Official.models | Where-Object { $_.slug -ceq $id }) | Select-Object -First 1
        if (-not $entry) {
            continue
        }
        if (-not $entry.base_instructions) {
            Set-Value $entry 'base_instructions' $entry.model_messages.instructions_template
        }
        if (-not ($entry.base_instructions -is [string]) -or -not $entry.base_instructions.Trim()) { throw 'Invalid Codex model metadata.' }
        Set-Value $entry 'visibility' 'list'
        Set-Value $entry 'supported_in_api' $true
        Set-Value $entry 'priority' $result.Count
        Set-Value $entry 'use_responses_lite' $false
        Set-Value $entry 'prefer_websockets' $false
        Set-Value $entry 'supports_reasoning_effort_updates' $false
        $result += $entry
    }
    return [pscustomobject]@{ models = $result }
}

function Merge-Json([string]$Original, $Values) {
    $document = [pscustomobject]@{}
    if ($Original.Trim()) {
        try { $document = ConvertFrom-Json -InputObject $Original } catch { throw (Text 'Файл настроек повреждён. Изменения не внесены.' 'Invalid settings file. No changes were made.') }
    }
    if ($document -isnot [pscustomobject]) { throw 'Settings must be a JSON object.' }
    foreach ($name in $Values.Keys) { Set-Value $document $name $Values[$name] }
    return (($document | ConvertTo-Json -Depth 100) + "`n")
}

function Add-DesktopChanges($Changes, [string]$LocalData, [string]$Key, [string[]]$Models) {
    $library = Join-Path $LocalData 'Claude-3p/configLibrary'
    $profile = @{
        inferenceProvider = 'gateway'; inferenceGatewayBaseUrl = $script:ClaudeBase
        inferenceGatewayAuthScheme = 'bearer'; inferenceGatewayApiKey = $Key; inferenceModels = @($Models)
    }
    Add-Change $Changes (Join-Path $LocalData 'Claude/claude_desktop_config.json') { param($original) Merge-Json $original @{ deploymentMode = '3p' } }
    Add-Change $Changes (Join-Path $LocalData 'Claude-3p/claude_desktop_config.json') { param($original) Merge-Json $original @{ deploymentMode = '3p' } }
    Add-Change $Changes (Join-Path $library ($script:DesktopProfileId + '.json')) { param($original) Merge-Json $original $profile }
    Add-Change $Changes (Join-Path $library '_meta.json') {
        param($original)
        $meta = Merge-Json $original @{} | ConvertFrom-Json
        if ($null -ne $meta.entries -and $meta.entries -isnot [array]) { throw 'Invalid Claude Desktop profile list.' }
        $entries = @($meta.entries | Where-Object { $null -ne $_ -and $_.id -ne $script:DesktopProfileId })
        $entries += [pscustomobject]@{ id = $script:DesktopProfileId; name = 'WORKERHUB' }
        Set-Value $meta 'entries' $entries
        Set-Value $meta 'appliedId' $script:DesktopProfileId
        ($meta | ConvertTo-Json -Depth 100) + "`n"
    }
}
function Quote-Toml([string]$Value) { return (ConvertTo-Json -InputObject $Value -Compress) }

function Get-TomlTablePath([string]$Header) {
    # TOML table keys can be bare, double quoted, or literal quoted; dots in quotes are not separators.
    $keyPattern = '(?:[A-Za-z0-9_-]+|"(?:[^"\\\x00-\x1f]|\\(?:["\\bfnrt]|u[0-9A-Fa-f]{4}|U[0-9A-Fa-f]{8}))*"|\x27[^\x27\x00-\x1f]*\x27)'
    $pathPattern = $keyPattern + '(?:[ \t]*\.[ \t]*' + $keyPattern + ')*'
    $match = [regex]::Match($Header, '^[ \t]*\[\[[ \t]*(?<path>' + $pathPattern + ')[ \t]*\]\][ \t]*(?:#.*)?$')
    if (-not $match.Success) {
        $match = [regex]::Match($Header, '^[ \t]*\[[ \t]*(?<path>' + $pathPattern + ')[ \t]*\][ \t]*(?:#.*)?$')
    }
    if (-not $match.Success) {
        throw (Text 'Не удалось прочитать секцию config.toml. Настройки не изменены.' 'Could not read a config.toml section. Settings were not changed.')
    }
    foreach ($token in [regex]::Matches($match.Groups['path'].Value, $keyPattern)) {
        $key = $token.Value
        if ($key.StartsWith("'")) { $key.Substring(1, $key.Length - 2) }
        elseif ($key.StartsWith('"')) {
            # TOML's eight-digit Unicode escape is not JSON syntax. Convert it to UTF-16 escapes first.
            $jsonKey = [regex]::Replace($key, '\\(?:U([0-9A-Fa-f]{8})|.)', [Text.RegularExpressions.MatchEvaluator]{
                param($escape)
                if (-not $escape.Groups[1].Success) { return $escape.Value }
                $point = [Convert]::ToInt32($escape.Groups[1].Value, 16)
                $characters = [char]::ConvertFromUtf32($point)
                return (($characters.ToCharArray() | ForEach-Object { '\u{0:x4}' -f [int]$_ }) -join '')
            })
            ConvertFrom-Json -InputObject $jsonKey
        } else { $key }
    }
}

function Update-Codex([string]$Original, [string]$Model, [string]$Catalog) {
    # Standard TOML is edited line by line. Refuse unusual syntax instead of damaging it.
    if ($Original -match '"""|\x27\x27\x27' -or $Original -match '(?m)^\s*model_providers\s*(?:=|\.)') {
        throw 'This Codex config uses multiline/inline TOML. It was not changed. Configure WORKERHUB manually or use a separate CODEX_HOME.'
    }
    $output = New-Object 'Collections.Generic.List[string]'
    $section = @()
    $drop = $false
    foreach ($line in ($Original -split '\r?\n')) {
        if ($line -match '^\s*\[') {
            $section = @(Get-TomlTablePath $line)
            $drop = $section.Count -ge 2 -and $section[0] -ceq 'model_providers' -and $section[1] -ceq 'workerhub'
        }
        if ($drop) { continue }
        if ($section.Count -eq 1 -and $section[0] -ceq 'model_providers' -and $line -match '^\s*["\x27]?workerhub') { throw 'Unsupported inline WORKERHUB provider; config was not changed.' }
        if ($section.Count -eq 0 -and $line -match '^\s*["\x27]?(model|model_provider|model_catalog_json)["\x27]?\s*=') {
            if ($line -notmatch '^\s*(model|model_provider|model_catalog_json)\s*=\s*(?:"(?:[^"\\]|\\.)*"|\x27[^\x27]*\x27)\s*(?:#.*)?$') {
                throw 'Unsupported Codex model setting; config was not changed.'
            }
            continue
        }
        $output.Add($line)
    }
    $prefix = @(
        ('model = ' + (Quote-Toml $Model)), 'model_provider = "workerhub"',
        ('model_catalog_json = ' + (Quote-Toml $Catalog)), ''
    ) -join "`r`n"
    $provider = @(
        '', '[model_providers.workerhub]', 'name = "WORKERHUB"',
        ('base_url = ' + (Quote-Toml $script:ApiBase)), 'wire_api = "responses"', 'supports_websockets = false',
        'env_key = "WORKERHUB_API_KEY"', ''
    ) -join "`r`n"
    return ($prefix + "`r`n" + (($output -join "`r`n").Trim([char[]]"`r`n")) + "`r`n" + $provider)
}

function Add-Change($Changes, [string]$Path, [scriptblock]$Render) {
    $before = $null
    $original = ''
    if ([IO.File]::Exists($Path)) {
        $before = [IO.File]::ReadAllBytes($Path)
        $original = $script:Utf8.GetString($before).TrimStart([char]0xFEFF)
    }
    $after = $script:Utf8.GetBytes((& $Render $original))
    if ($null -eq $before -or [Convert]::ToBase64String($before) -cne [Convert]::ToBase64String($after)) {
        $Changes.Add([pscustomobject]@{ Path = $Path; Before = $before; After = $after })
    }
}

function Same-File([string]$Path, $Bytes) {
    if (-not [IO.File]::Exists($Path)) { return ($null -eq $Bytes) }
    if ($null -eq $Bytes) { return $false }
    return [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) -ceq [Convert]::ToBase64String($Bytes)
}

function Set-UserVariable([string]$Name, $Value) {
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
    [Environment]::SetEnvironmentVariable($Name, $Value, 'Process')
}

function Save-Connection($Changes, $Variables) {
    foreach ($change in $Changes) {
        if (-not (Same-File $change.Path $change.Before)) { throw 'Settings changed in another application. Please try again.' }
    }
    $previous = @{}
    foreach ($name in $Variables.Keys) { $previous[$name] = [Environment]::GetEnvironmentVariable($name, 'User') }
    $tag = (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $committed = New-Object 'Collections.Generic.List[object]'
    $environmentTouched = $false
    try {
        foreach ($change in $Changes) {
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($change.Path))
            $temporary = $change.Path + '.' + $tag + '.tmp'
            try {
                [IO.File]::WriteAllBytes($temporary, $change.After)
                if (-not (Same-File $change.Path $change.Before)) { throw 'Settings changed in another application. Please try again.' }
                if ($null -ne $change.Before) { [IO.File]::Replace($temporary, $change.Path, ($change.Path + '.workerhub-' + $tag + '.bak')) }
                else { [IO.File]::Move($temporary, $change.Path) }
                $committed.Add($change)
            } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
        }
        $environmentTouched = $true
        foreach ($name in $Variables.Keys) { Set-UserVariable $name $Variables[$name] }
    } catch {
        $failure = $_
        $rollbackFailed = $false
        if ($environmentTouched) {
            foreach ($name in $previous.Keys) { try { Set-UserVariable $name $previous[$name] } catch { $rollbackFailed = $true } }
        }
        for ($i = $committed.Count - 1; $i -ge 0; $i--) {
            $change = $committed[$i]
            try {
                if (-not (Same-File $change.Path $change.After)) { throw 'Settings changed externally.' }
                if ($null -eq $change.Before) { [IO.File]::Delete($change.Path) }
                else { [IO.File]::WriteAllBytes($change.Path, $change.Before) }
            } catch { $rollbackFailed = $true }
        }
        if ($rollbackFailed) { throw (Text 'Не удалось полностью восстановить настройки. Восстановите соседние файлы .workerhub-*.bak.' 'Could not fully restore settings. Restore the adjacent .workerhub-*.bak files.') }
        throw $failure
    }
}
function Notify-Environment {
    try {
        if (-not ('WorkerhubEnvironment' -as [type])) {
            Add-Type 'using System; using System.Runtime.InteropServices; public static class WorkerhubEnvironment { [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessageTimeout(IntPtr window, uint message, UIntPtr parameter, string value, uint flags, uint timeout, out UIntPtr result); }'
        }
        $result = [UIntPtr]::Zero
        [void][WorkerhubEnvironment]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'Environment', 2, 2000, [ref]$result)
    } catch { }
}
function Start-Workerhub {
    if ($env:OS -ne 'Windows_NT') { throw 'Windows is required.' }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { throw 'Open workerhub.cmd in an interactive terminal.' }
    [Console]::OutputEncoding = $script:Utf8
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Write-Host "`nWORKERHUB"
    if ((Choose 'Language / Язык' @('Русский', 'English')) -eq 0) { $script:Language = 'ru' }
    $targets = @('Claude Desktop', 'Claude Code CLI', 'Codex', 'Codex CLI')
    $target = Choose (Text 'Что подключить?' 'What would you like to connect?') $targets
    $claude = $target -lt 2
    $key = $null
    try {
        do {
            $secure = Read-Host (Text 'API-ключ WORKERHUB' 'WORKERHUB API key') -AsSecureString
            $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
            try { $key = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
            finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer); $secure.Dispose() }
            $valid = $key -cmatch '^[\x21-\x7e]{8,512}$' -and $key -notmatch '^Bearer\b'
            if (-not $valid) { Write-Host (Text 'Введите ключ без пробелов и без Bearer.' 'Enter the key without spaces or a Bearer prefix.') }
        } until ($valid)
        $live = Get-Json ($script:ApiBase + '/models')
        if ($null -eq $live.data) { throw (Text 'Не удалось получить модели WORKERHUB.' 'Could not load WORKERHUB models.') }
        $ids = @($live.data | ForEach-Object { $_.id } | Where-Object { $_ -is [string] -and $_ -cmatch '^[a-zA-Z0-9][a-zA-Z0-9._:/-]{0,199}$' } | Sort-Object -Unique)
        if ($claude) {
            $ids = @($ids | Where-Object { $_ -match '(?:^|/)claude[-.]' -and $_ -notmatch 'image|audio|embed' } | Sort-Object @{ Expression = { if ($_ -match 'sonnet') { 0 } else { 1 } } }, { $_ })
            if ($target -eq 0) { $ids = @($ids | Where-Object { $_ -match '^(anthropic/)?claude-(sonnet|opus|haiku|fable)-' }) }
        } else {
            $ids = @($ids | Where-Object { $_ -match '(?:^|/)(?:gpt[-.]|codex[-.]|o[134](?:-|$))' -and $_ -notmatch 'image|audio|tts|realtime|transcrib|embed|search' } | Sort-Object @{ Expression = { if ($_ -match 'sol') { 0 } else { 1 } } }, { $_ })
            $official = Get-Json 'https://raw.githubusercontent.com/openai/codex/main/codex-rs/models-manager/models.json'
            $catalog = Get-Catalog $ids $official
            $ids = @($catalog.models | ForEach-Object { $_.slug })
        }
        $model = $ids[(Choose (Text 'Модель' 'Model') $ids)]
        $changes = New-Object 'Collections.Generic.List[object]'
        $variables = @{}
        if ($target -eq 0) {
            $orderedModels = @($model) + @($ids | Where-Object { $_ -cne $model })
            Add-DesktopChanges $changes ([Environment]::GetFolderPath('LocalApplicationData')) $key $orderedModels
        } elseif ($target -eq 1) {
            $variables = @{
                ANTHROPIC_BASE_URL = $script:ClaudeBase; ANTHROPIC_AUTH_TOKEN = $key; ANTHROPIC_API_KEY = $null
                ANTHROPIC_MODEL = $model; CLAUDE_CODE_USE_BEDROCK = '0'; CLAUDE_CODE_USE_VERTEX = '0'; CLAUDE_CODE_USE_FOUNDRY = '0'
            }
            foreach ($family in @('SONNET', 'OPUS', 'HAIKU', 'FABLE')) {
                $alias = @($ids | Where-Object { $_ -match $family }) | Select-Object -First 1
                if (-not $alias) { $alias = $model }
                $variables["ANTHROPIC_DEFAULT_${family}_MODEL"] = $alias
            }
            $variables['CLAUDE_CODE_SUBAGENT_MODEL'] = $variables.ANTHROPIC_DEFAULT_SONNET_MODEL
            $variables['ANTHROPIC_SMALL_FAST_MODEL'] = $variables.ANTHROPIC_DEFAULT_HAIKU_MODEL
        } else {
            $variables['WORKERHUB_API_KEY'] = $key
            $directory = Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex'
            if ($env:CODEX_HOME) { $directory = [IO.Path]::GetFullPath($env:CODEX_HOME) }
            $catalogPath = Join-Path $directory 'workerhub-models.json'
            Add-Change $changes $catalogPath { ($catalog | ConvertTo-Json -Depth 100) + "`n" }
            Add-Change $changes (Join-Path $directory 'config.toml') { param($original) Update-Codex $original $model $catalogPath }
        }
        Save-Connection $changes $variables
        if ($variables.Count) { Notify-Environment }
        Write-Host (Text "`nГотово. Полностью перезапустите приложение или терминал." "`nDone. Fully restart the app or terminal.")
    } finally { $key = $null }
}
if (-not $LibraryOnly) {
    try { Start-Workerhub }
    catch [OperationCanceledException] { Write-Host (Text "`nОтменено." "`nCancelled.") }
    catch {
        # Do not print raw exception details that might include configuration or credentials.
        Write-Host (Text "`nНе удалось завершить настройку." "`nSetup did not complete.") -ForegroundColor Red
        Write-Host ($_.Exception.Message)
        exit 1
    }
}
