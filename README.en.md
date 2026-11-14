<div align="center">

# WORKERHUB Connect

**Your apps. Your key. WORKERHUB models.**

Connect Claude and Codex to WORKERHUB with a single Windows file.

[Download workerhub.cmd](https://github.com/pilyu9in/workerhub-connect/releases/latest/download/workerhub.cmd) · [Русский](README.md) · [WORKERHUB](https://workerhub.cc) · [Support](https://t.me/workerhub_support)

Windows 10 / 11 · PowerShell 5.1 · Русский / English · MIT

</div>

---

## Get started

1. **Download** [workerhub.cmd](https://github.com/pilyu9in/workerhub-connect/releases/latest/download/workerhub.cmd) and double-click it. Your chosen app must already be installed.
2. **Choose your language and app** with ↑ ↓ and Enter. Press Esc or Ctrl+C to cancel.
3. **Paste your API key** from Overview in the WORKERHUB dashboard and select a model. Key input is hidden.
4. **Fully restart your app or terminal**, including background processes. You are ready to go.

Run the file again to connect another app or change the default model. Codex and Codex CLI share settings.

```text
WORKERHUB

What would you like to connect?
  Claude Desktop
  Claude Code CLI
> Codex
  Codex CLI
```

One CMD file with embedded PowerShell. No Node.js, npm, or administrator access required. It configures connections without installing or updating apps.

## Supported apps

| App | What gets configured |
| --- | --- |
| **Claude Desktop** | A WORKERHUB third-party gateway profile, API key and available Claude models. The selected model is listed first. |
| **Claude Code CLI** | Windows user environment variables for the gateway, key, default model and Claude family aliases. |
| **Codex** | The WORKERHUB provider, default model and a local catalog of compatible models in the shared Codex settings. |
| **Codex CLI** | The same connection as the Codex app. Existing official login is preserved. |

### Models and billing

Available models are fetched from the current WORKERHUB catalog on every run. Codex entries are matched against official client model metadata. Only suitable text models are included; image and audio models are excluded.

Models **are not downloaded to your computer**. Inference goes through WORKERHUB and uses your account balance at the current rates. Setup makes no paid inference requests and does not validate your key by generating a response; the first app request will test it.

Claude Code CLI gets a default model and available family aliases rather than a separate full picker catalog. Run the script again to refresh the Desktop/Codex model lists.

## How it works

| Client | Gateway URL |
| --- | --- |
| Claude Desktop / Claude Code CLI | `https://workerhub.cc/worker-api` |
| Codex / Codex CLI | `https://workerhub.cc/worker-api/v1` |

Claude uses the Anthropic-compatible gateway root; the client appends `/v1/messages`. Codex uses the Responses API. The script sets the correct address automatically.

<details>
<summary><strong>Settings that change</strong></summary>

**Claude Code CLI:** Windows user variables `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`, `ANTHROPIC_DEFAULT_*_MODEL` family aliases and helper-model settings. `ANTHROPIC_API_KEY` is cleared, and Bedrock/Vertex/Foundry modes are disabled to avoid conflicting routes.

**Claude Desktop:** `deploymentMode = "3p"` in `%LOCALAPPDATA%\Claude\claude_desktop_config.json` and `%LOCALAPPDATA%\Claude-3p\claude_desktop_config.json`. A dedicated WORKERHUB profile is added and activated in `%LOCALAPPDATA%\Claude-3p\configLibrary`; other profiles are retained.

**Codex / Codex CLI:** The selected model, `model_providers.workerhub` provider and `workerhub-models.json` path in `%USERPROFILE%\.codex\config.toml`. `CODEX_HOME` is respected when set. The key goes into the Windows user variable `WORKERHUB_API_KEY`. `auth.json` is unchanged.

Keys are stored locally in environment variables or an app profile **without additional encryption**. Do not publish those settings or backups containing a key.

</details>

<details>
<summary><strong>Backups and restoring settings</strong></summary>

Before an existing file changes, an exact adjacent `filename.workerhub-DATE-ID.bak` copy is created. A failed write triggers an attempt to roll back changes from that run. Concurrent changes from another app abort configuration.

For a manual restore, close the app and restore the relevant adjacent `.bak` file. Newly created configuration files have no previous backup; remove them manually if no longer needed.

Environment variables do not have file backups; automatic rollback applies to a failed current run. To switch providers later, restore previous Windows user variable values or use your provider-management tool. Claude Desktop can also switch to its previous profile. For Codex, restore the previous `config.toml` and remove `WORKERHUB_API_KEY` if no longer needed.

</details>

## Troubleshooting

| Problem | Next step |
| --- | --- |
| App still uses the old connection | Quit all app/background processes and reopen. For CLI, open a new terminal and restart its parent IDE if applicable. Client-local overrides can take precedence over user variables. |
| Catalog could not load | Check connectivity to WORKERHUB and GitHub, then retry. No settings are written before the catalog loads. |
| App reports a key or balance error | Check your dashboard key and balance. Paste the key alone, without spaces or `Bearer`. |
| Codex Desktop models are missing | Restart the app. Some versions depend on official sign-in for the picker; the script preserves existing login. Try Codex CLI if necessary. |
| `config.toml` update was refused | Normal tables, including quoted project/plugin paths, are supported. Multiline strings and some inline/dotted provider definitions are deliberately rejected. Use a separate `CODEX_HOME` or configure the provider manually. |
| File opens in an editor | Save the actual `workerhub.cmd`, not an HTML page or `.txt`. Use an interactive Windows console. |

## Development

All executable code lives in [workerhub.cmd](workerhub.cmd). The CMD wrapper starts embedded PowerShell with a process-scoped execution-policy override; it does not change the system execution policy.

Keep the script UTF-8 **without BOM** with **CRLF** line endings, as enforced by `.gitattributes`. GitHub Actions checks Windows PowerShell 5.1 syntax, TOML editing and preservation of unrelated settings without real keys or inference requests.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/smoke.ps1
```

[Open an issue](https://github.com/pilyu9in/workerhub-connect/issues) with your app and error text. Remove API keys from any logs or settings you share.

## License

[MIT](LICENSE). Claude and Codex belong to their respective owners. WORKERHUB Connect is a separate third-party connection utility.
