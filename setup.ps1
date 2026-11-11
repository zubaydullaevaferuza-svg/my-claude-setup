# setup.ps1 - install SkillSpector, Ponytail, LemoOpuscar, Agent Reach and FreeLLMAPI
# for Claude Code on Windows. Every install step asks first ("y" to go ahead).
#
# Run from a normal (non-admin) PowerShell window:
#   powershell -ExecutionPolicy Bypass -File .\setup.ps1
#
# What it does NOT do (on purpose):
#   - no logins to X / Reddit / LinkedIn etc. for Agent Reach
#   - no API keys (run "agent-reach configure ..." yourself; add FreeLLMAPI keys in its dashboard)
#   - no "freellmapi setup-claude" / launch: Claude Code is not switched to FreeLLMAPI
#   - no FreeLLMAPI Docker "autoupdate" profile (it mounts the Docker socket)

$ErrorActionPreference = 'Stop'
$Results = [ordered]@{}

function Ask($msg) {
    $a = Read-Host "$msg [y/N]"
    return $a -match '^(y|yes)$'
}

function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User') + ';' +
                "$env:USERPROFILE\.local\bin"
}

function Get-Ver($cmd, $arg = '--version') {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { return $null }
    try { return ((& $cmd $arg 2>&1) | Select-Object -First 1).ToString().Trim() } catch { return $null }
}

function Step($name, [scriptblock]$body) {
    Write-Host "`n=== $name ===" -ForegroundColor Cyan
    try { & $body }
    catch {
        Write-Host "FAILED: $($_.Exception.Message)" -ForegroundColor Red
        $Results[$name] = 'FAILED'
        if (-not (Ask 'Continue with the next step?')) { Show-Summary; exit 1 }
    }
}

function Show-Summary {
    Write-Host "`n=== Summary ===" -ForegroundColor Cyan
    $Results.GetEnumerator() | ForEach-Object { '{0,-14} {1}' -f $_.Key, $_.Value } | Write-Host
    Write-Host "`nRestart Claude Code so the plugins and the MCP server load." -ForegroundColor Yellow
}

Refresh-Path

# ---------------------------------------------------------------- 0. prerequisites
Step 'Prerequisites' {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Host 'winget not found: install missing tools by hand (App Installer from the Microsoft Store).' -ForegroundColor Yellow
    }
    $missing = @()

    $git = Get-Ver git;      Write-Host "git:    $git"
    if (-not $git) { $missing += @{ n = 'git'; id = 'Git.Git' } }

    $node = Get-Ver node;    Write-Host "node:   $node"
    if (-not $node -or [int]($node -replace '^v(\d+).*', '$1') -lt 20) { $missing += @{ n = 'Node 20+ (LTS)'; id = 'OpenJS.NodeJS.LTS' } }

    $py = $null
    foreach ($v in '3.13', '3.12') {
        if (Get-Command py -ErrorAction SilentlyContinue) {
            & py "-$v" --version 2>$null | Out-Null
            if ($LASTEXITCODE -eq 0) { $py = $v; break }
        }
    }
    Write-Host "python: $(if ($py) { $py } else { 'no 3.12/3.13 found' })  (3.14 is NOT ok: yara-python has no wheel)"
    if (-not $py) { $missing += @{ n = 'Python 3.13'; id = 'Python.Python.3.13' } }

    $uv = Get-Ver uv;        Write-Host "uv:     $uv"
    if (-not $uv) { $missing += @{ n = 'uv'; id = 'astral-sh.uv' } }

    $ff = Get-Ver ffmpeg '-version'; Write-Host "ffmpeg: $ff"
    if (-not $ff -or [int](($ff -replace '^ffmpeg version n?(\d+).*', '$1') -as [int]) -lt 7) {
        $missing += @{ n = 'ffmpeg 7+'; id = 'Gyan.FFmpeg' }
    }

    $claude = Get-Ver claude; Write-Host "claude: $claude"
    if (-not $claude) { throw 'Claude Code (claude) is not on PATH. Install it first.' }

    foreach ($m in $missing) {
        if (Ask "Missing: $($m.n). Install with 'winget install -e --id $($m.id)'?") {
            winget install -e --id $m.id --accept-source-agreements --accept-package-agreements
        } else { Write-Host "Skipped $($m.n)" -ForegroundColor Yellow }
    }
    Refresh-Path
    $Results['Prerequisites'] = if ($missing.Count) { "installed/skipped: $($missing.n -join ', ')" } else { 'all present' }
}

# ---------------------------------------------------------------- 1. SkillSpector
Step 'SkillSpector' {
    if (-not (Ask 'Install NVIDIA SkillSpector (uv tool, Python 3.13) and add it as an MCP server?')) { $Results['SkillSpector'] = 'skipped'; return }
    uv tool install --python 3.13 "skillspector[mcp] @ git+https://github.com/NVIDIA/skillspector.git"
    if ($LASTEXITCODE) { throw 'uv tool install failed' }
    Refresh-Path
    skillspector --help | Out-Null
    claude mcp add skillspector -- skillspector mcp
    $Results['SkillSpector'] = "installed $(skillspector --version)"
}

function Scan($repo) {
    if (-not (Get-Command skillspector -ErrorAction SilentlyContinue)) { Write-Host 'SkillSpector not installed: no scan.' -ForegroundColor Yellow; return }
    if (-not (Ask "Scan github.com/$repo with SkillSpector first? (can take 5-25 min)")) { return }
    skillspector scan "https://github.com/$repo" --no-llm
    Write-Host "Note: all four repos were rated DO_NOT_INSTALL in an earlier scan; on review the CRITICAL hits were false positives (see README)." -ForegroundColor Yellow
}

# ---------------------------------------------------------------- 3. Ponytail
Step 'Ponytail' {
    Scan 'DietrichGebert/ponytail'
    if (-not (Ask 'Install Ponytail (DietrichGebert/ponytail, NOT the MoxyWolfLLC one)?')) { $Results['Ponytail'] = 'skipped'; return }
    claude plugin marketplace add DietrichGebert/ponytail
    claude plugin install ponytail@ponytail
    if ($LASTEXITCODE) { throw 'plugin install failed' }
    $Results['Ponytail'] = 'installed'
}

# ---------------------------------------------------------------- 4. LemoOpuscar
Step 'LemoOpuscar' {
    Scan 'lemomo-ai/lemo-opuscar'
    Write-Host 'Note: on first use its setup.sh clones the ~190 MB repo and runs npm/pip installs.' -ForegroundColor Yellow
    if (-not (Ask 'Install LemoOpuscar?')) { $Results['LemoOpuscar'] = 'skipped'; return }
    claude plugin marketplace add lemomo-ai/lemo-opuscar
    claude plugin install lemo-opuscar@lemolab
    if ($LASTEXITCODE) { throw 'plugin install failed' }
    $Results['LemoOpuscar'] = 'installed'
}

# ---------------------------------------------------------------- 5. Agent Reach
Step 'Agent Reach' {
    Scan 'Panniantong/Agent-Reach'
    Write-Host 'Note: Agent Reach can reuse logins from browsers already connected to it. No logins are set up here.' -ForegroundColor Yellow
    if (-not (Ask 'Install Agent Reach from its GitHub release (NOT the PyPI package)?')) { $Results['Agent Reach'] = 'skipped'; return }
    uv tool install https://github.com/Panniantong/Agent-Reach/releases/latest/download/agent-reach.zip
    if ($LASTEXITCODE) { throw 'uv tool install failed' }
    Refresh-Path
    if (Ask "Run 'agent-reach setup' (turns on the default no-login channels and installs its skill)?") {
        agent-reach setup
    }
    $Results['Agent Reach'] = "installed $(agent-reach version 2>$null)"
}

# ---------------------------------------------------------------- 6. FreeLLMAPI
Step 'FreeLLMAPI' {
    Scan 'tashfeenahmed/freellmapi'
    if (-not (Ask 'Download and run the FreeLLMAPI Windows installer from the official GitHub release?')) { $Results['FreeLLMAPI'] = 'skipped'; return }
    $rel = Invoke-RestMethod 'https://api.github.com/repos/tashfeenahmed/freellmapi/releases/latest' -Headers @{ 'User-Agent' = 'setup-script' }
    $asset = $rel.assets | Where-Object { $_.name -like '*.exe' } | Select-Object -First 1
    if (-not $asset) { throw "No .exe asset in release $($rel.tag_name)" }
    $out = Join-Path $env:TEMP $asset.name
    Write-Host "Downloading $($asset.name) ($($rel.tag_name)) from $($asset.browser_download_url)"
    Invoke-WebRequest $asset.browser_download_url -OutFile $out
    $sig = Get-AuthenticodeSignature $out
    Write-Host "Signature: $($sig.Status) $($sig.SignerCertificate.Subject)"
    if ($sig.Status -ne 'Valid' -and -not (Ask 'Installer is not validly signed. Run it anyway?')) { $Results['FreeLLMAPI'] = 'downloaded, not run'; return }
    Start-Process $out -Wait
    Write-Host 'Open the dashboard: tray icon -> Open Dashboard (or http://127.0.0.1:31415). Add provider keys on the Keys page.' -ForegroundColor Green
    Write-Host 'Do NOT run "npx freellmapi setup-claude" unless you decide to route Claude Code through it.' -ForegroundColor Yellow
    $Results['FreeLLMAPI'] = "installed $($rel.tag_name)"
}

Show-Summary
