# my-claude-setup

`setup.ps1` installs these Claude Code add-ons on Windows, in this order, asking before each step:

1. Prerequisites: git, Node 20+, Python 3.12/3.13 (not 3.14), uv, ffmpeg 7+ (via winget)
2. NVIDIA SkillSpector (security scanner, also added as an MCP server)
3. Ponytail (`DietrichGebert/ponytail`)
4. LemoOpuscar (`lemomo-ai/lemo-opuscar`)
5. Agent Reach (`Panniantong/Agent-Reach`, from its GitHub release, not PyPI)
6. FreeLLMAPI (`tashfeenahmed/freellmapi`, official Windows installer)

```powershell
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

Restart Claude Code afterwards.

## Scan results (SkillSpector 2.12.0, `--no-llm`, 2026-11-11)

All four were rated **DO_NOT_INSTALL** (score 100). The CRITICAL findings were checked by hand and are false positives:

| Repo (commit) | Findings | Coverage | Notes |
|---|---|---|---|
| ponytail `96608e0` | 1 CRIT, 36 HIGH | 82.5% | CRITICAL is a benchmark sending an API key to api.anthropic.com. Most HIGH are in tests/benchmarks. |
| lemo-opuscar `9eb7739` | 3 CRIT, 552 HIGH | 43.5% | CRITICALs are demo scripts passing Wikimedia URLs as subprocess args (no shell). First use clones the repo and runs npm/pip installs. |
| Agent-Reach `c70ae6d` | 1 CRIT, 25 HIGH | 97.5% | CRITICAL is a request to the local browser's debugging port on 127.0.0.1. Can reuse logins from browsers already connected to it. |
| freellmapi `3b22290` | 0 CRIT, 203 HIGH | 0% (timed out) | Mostly `.env` mentions. Docker binds to localhost. Only the optional `autoupdate` profile mounts the Docker socket, so don't enable it. |

## Left for you to do by hand

- Agent Reach API keys: run `agent-reach configure <name>` yourself. No logged-in platforms are set up.
- FreeLLMAPI: add provider keys in its dashboard (tray icon, then **Open Dashboard**). The script doesn't run `setup-claude`.
