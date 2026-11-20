<div align="center">

# WORKERHUB Connect

**Your apps. Your key. WORKERHUB models.**

Connect Claude and Codex to WORKERHUB with one setup file for Windows or macOS.

[Download for Windows](https://github.com/pilyu9in/workerhub-connect/releases/latest/download/workerhub.cmd) · [Download for macOS](https://github.com/pilyu9in/workerhub-connect/releases/latest/download/workerhub-macos.command) · [Releases and SHA-256](https://github.com/pilyu9in/workerhub-connect/releases) · [Русский](README.md) · [WORKERHUB](https://workerhub.cc) · [Support](https://t.me/workerhub_support)

Windows 10 / 11 · PowerShell 5.1 · macOS · Python 3.11+ · Русский / English · MIT

</div>

---

## Get started

1. Download the setup file for your system. Your chosen app must already be installed.
   - **Windows:** double-click [workerhub.cmd](https://github.com/pilyu9in/workerhub-connect/releases/latest/download/workerhub.cmd).
   - **macOS:** Python 3.11 or newer is required. Download [workerhub-macos.command](https://github.com/pilyu9in/workerhub-connect/releases/latest/download/workerhub-macos.command), open Terminal and run:
     ```sh
     sh ~/Downloads/workerhub-macos.command
     ```
2. **Choose your language and app** with ↑ ↓ and Enter. Esc cancels the selection.
3. **Paste your API key** from Overview in the WORKERHUB dashboard and select a model. Key input is hidden.
4. **Fully restart your app or terminal**, including background processes.

Run the file again to connect another app or change the default model. Codex and Codex CLI share settings.

```text
WORKERHUB

What would you like to connect?
  Claude Desktop
  Claude Code CLI
> Codex
  Codex CLI
```

The setup files only configure connections; they do not install or update Claude or Codex. Windows uses built-in PowerShell 5.1; macOS requires Python 3.11+ and Terminal. No Node.js or administrator access is required.

## Supported apps

| App | What gets configured |
| --- | --- |
| **Claude Desktop** | A WORKERHUB third-party gateway profile, API key and available Claude models on Windows or macOS. The selected model is listed first. |
| **Claude Code CLI** | Gateway, key, default model and Claude family aliases in Windows user environment or `~/.claude/settings.json` on macOS. |
| **Codex** | The WORKERHUB provider, default model and a local catalog of compatible models in shared Codex settings on Windows or macOS. |
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

**Claude Code CLI:** Windows user variables `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN`, `ANTHROPIC_MODEL`, family aliases and helper-model settings. On macOS the same values are written inside the `env` object in `~/.claude/settings.json`. On both systems `ANTHROPIC_API_KEY` is cleared and Bedrock/Vertex/Foundry modes are disabled to avoid conflicting routes.

**Claude Desktop:** `deploymentMode = "3p"` is enabled in the Claude config directory and a dedicated WORKERHUB profile is activated. On Windows this is under `%LOCALAPPDATA%\Claude`; on macOS it is under `~/Library/Application Support/Claude`. Existing profiles are retained.

**Codex / Codex CLI:** The selected model, `model_providers.workerhub` provider and model catalog path are written to `config.toml`. The default directory is `%USERPROFILE%\.codex` on Windows and `~/.codex` on macOS; `CODEX_HOME` is respected on both. Windows stores the key in the `WORKERHUB_API_KEY` user variable. macOS stores it in `~/.workerhub/api-key` with owner-only permissions and uses a helper command when Codex requests it. `auth.json` is unchanged.

Keys are stored locally without additional encryption: in a Windows user variable or Claude Desktop profile, in Claude settings on macOS, or in the owner-only `~/.workerhub/api-key` file for Codex on macOS. Do not publish those settings or backups containing a key.

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
| macOS reports that Python is required | Install Python 3.11 or newer, then run the `.command` file from Terminal again. |
| macOS arrow keys do not work | Run the file in Terminal, not in an editor or without an interactive terminal. |
| Setup file opens as text | Save the actual setup file, not an HTML page or `.txt`; on Mac, run it from Terminal. |

## Source and download verification

Both release files come from the source at the version tag. The same release includes `SHA256SUMS.txt` with checksums for both files. If you saved your file in Downloads, compare the command output with the entry for your platform in `SHA256SUMS.txt`.

```powershell
Get-FileHash "$env:USERPROFILE\Downloads\workerhub.cmd" -Algorithm SHA256
```

```sh
shasum -a 256 ~/Downloads/workerhub-macos.command
```

## Development

The Windows setup is in [workerhub.cmd](workerhub.cmd); the macOS setup is in [workerhub-macos.command](workerhub-macos.command). The latter is a shell wrapper with embedded Python code; a separate macOS CI job checks the shell syntax and setup logic.

The Windows script uses UTF-8 without BOM and CRLF line endings. GitHub Actions runs Windows PowerShell checks and a separate macOS installer job, including shell syntax and configuration tests. Tests use temporary directories and fake keys; they do not send inference requests.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/smoke.ps1
```

```sh
sh -n workerhub-macos.command
python3 -m unittest discover -s tests -p 'test_macos_command.py' -v
```

[Open an issue](https://github.com/pilyu9in/workerhub-connect/issues) with your OS, app and error text. Remove API keys from any logs or settings you share.

## License

[MIT](LICENSE). Claude and Codex belong to their respective owners. WORKERHUB Connect is a separate third-party connection utility.
