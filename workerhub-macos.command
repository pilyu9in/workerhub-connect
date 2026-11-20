#!/bin/sh
""":"
if ! command -v python3 >/dev/null 2>&1 || ! python3 -I -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 11) else 1)' >/dev/null 2>&1; then
  printf '%s\n' 'WORKERHUB Connect for macOS requires Python 3.11 or newer.' 'Install Python from python.org, then open Terminal and run this file again.'
  exit 127
fi
exec python3 -I "$0" "$@"
: <<'# WORKERHUB_PYTHON_END'
":"""
from __future__ import annotations

import copy
import getpass
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import tomllib
import warnings
import uuid
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Callable

API_BASE = "https://workerhub.cc/worker-api/v1"
CLAUDE_BASE = "https://workerhub.cc/worker-api"
CODEX_MODELS_URL = "https://raw.githubusercontent.com/openai/codex/main/codex-rs/models-manager/models.json"
MAX_RESPONSE_BYTES = 8_000_000
PROFILE_ID = "8d8eea95-a59c-4c2a-8671-776f726b6572"
MODEL_ID_PATTERN = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$")
DESKTOP_MODEL_PATTERN = re.compile(r"^(?:anthropic/)?claude-(?:sonnet|opus|haiku|fable)-", re.IGNORECASE)
CLAUDE_PATTERN = re.compile(r"(?:^|/)claude[-.]", re.IGNORECASE)
CODEX_PATTERN = re.compile(r"(?:^|/)(?:gpt[-.]|codex[-.]|o[134](?:-|$))", re.IGNORECASE)
EXCLUDED_CODEX_PATTERN = re.compile(r"image|audio|tts|realtime|transcrib|embed|search", re.IGNORECASE)
LANGUAGE = "ru"


def text(language: str, ru: str, en: str) -> str:
    return ru if language == "ru" else en


def tr(ru: str, en: str) -> str:
    return text(LANGUAGE, ru, en)


class SetupError(Exception):
    """A safe-to-display setup error without request secrets."""


@dataclass
class Change:
    path: Path
    before: bytes | None
    after: bytes
    before_mode: int | None
    after_mode: int


def read_menu_key(fd: int) -> str:
    """Read one key without TextIO buffering consuming terminal escape bytes."""
    import select

    first = os.read(fd, 1)
    if first in (b"\r", b"\n"):
        return "enter"
    if first in (b"", b"\x03", b"\x04"):
        return "cancel"
    if first != b"\x1b":
        return "other"
    if not select.select([fd], [], [], 0.12)[0]:
        return "cancel"
    second = os.read(fd, 1)
    if second not in (b"[", b"O"):
        return "cancel"
    if not select.select([fd], [], [], 0.12)[0]:
        return "cancel"
    third = os.read(fd, 1)
    return {
        b"[A": "up", b"OA": "up",
        b"[B": "down", b"OB": "down",
        b"[H": "home", b"OH": "home",
        b"[F": "end", b"OF": "end",
    }.get(second + third, "other")


def choose(title: str, options: list[str], page_size: int = 8) -> int:
    import termios
    import tty

    if not options:
        raise SetupError(tr("В этом списке нет вариантов для выбора.", "There are no options in this list."))
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise SetupError(tr("Запустите файл в приложении Terminal, чтобы выбрать вариант стрелками.", "Run this file in Terminal to choose with the arrow keys."))

    count = min(page_size, len(options))
    selected = 0
    print(f"\n{title}")
    for _ in range(count):
        print()
    sys.stdout.write(f"\033[{count}A")
    sys.stdout.flush()
    original = termios.tcgetattr(sys.stdin.fileno())
    width = max(20, shutil.get_terminal_size((80, 24)).columns - 2)
    try:
        tty.setraw(sys.stdin.fileno(), termios.TCSANOW)
        while True:
            first = max(0, min(selected - count + 1, len(options) - count))
            for row in range(count):
                index = first + row
                marker = ">" if index == selected else " "
                label = options[index]
                line = f" {marker} {label}"
                if len(line) > width:
                    line = line[: width - 3] + "..."
                sys.stdout.write("\r\033[2K" + line + "\r\n")
            sys.stdout.write(f"\033[{count}A")
            sys.stdout.flush()
            key = read_menu_key(sys.stdin.fileno())
            if key == "enter":
                sys.stdout.write(f"\033[{count}B\r\n")
                sys.stdout.flush()
                return selected
            if key == "up":
                selected = (selected - 1) % len(options)
            elif key == "down":
                selected = (selected + 1) % len(options)
            elif key == "home":
                selected = 0
            elif key == "end":
                selected = len(options) - 1
            elif key == "cancel":
                sys.stdout.write(f"\033[{count}B\r\n")
                sys.stdout.flush()
                raise SetupError(tr("Настройка отменена.", "Setup cancelled."))
    finally:
        termios.tcsetattr(sys.stdin.fileno(), termios.TCSAFLUSH, original)


def read_key() -> str:
    while True:
        try:
            with warnings.catch_warnings():
                warnings.simplefilter("error", getpass.GetPassWarning)
                key = getpass.getpass(tr("API-ключ WORKERHUB (ввод скрыт): ", "WORKERHUB API key (input is hidden): ")).strip()
        except getpass.GetPassWarning as exc:
            raise SetupError(tr("Не удалось скрыть ввод ключа.", "Could not hide API key input.")) from exc
        except (EOFError, KeyboardInterrupt) as exc:
            raise SetupError(tr("Настройка отменена.", "Setup cancelled.")) from exc
        if re.fullmatch(r"[\x21-\x7e]{8,512}", key) and not re.match(r"Bearer\b", key, re.IGNORECASE):
            return key
        print(tr("Ключ должен быть без пробелов и без префикса Bearer. Повторите ввод.", "Enter the key without spaces or the Bearer prefix."), file=sys.stderr)


def fetch_json(url: str) -> dict | list:
    try:
        result = subprocess.run(
            ["/usr/bin/curl", "--disable", "--fail", "--silent", "--proto", "=https",
             "--max-time", "25", "--max-filesize", str(MAX_RESPONSE_BYTES),
             "--header", "Accept: application/json", url],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True, timeout=30,
        )
        body = result.stdout
    except (subprocess.SubprocessError, OSError) as exc:
        raise SetupError(tr("Не удалось загрузить каталог моделей. Проверьте доступ к WORKERHUB и GitHub.", "Could not load the model catalog. Check access to WORKERHUB and GitHub.")) from exc
    if len(body) > MAX_RESPONSE_BYTES:
        raise SetupError(tr("Каталог моделей вернул слишком большой ответ.", "The model catalog response is too large."))
    try:
        result = json.loads(body)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SetupError(tr("Сервер вернул неверный формат каталога моделей.", "The server returned an invalid model catalog.")) from exc
    if not isinstance(result, (dict, list)):
        raise SetupError(tr("Сервер вернул неверный формат каталога моделей.", "The server returned an invalid model catalog."))
    return result


def model_ids(payload: dict | list) -> list[str]:
    entries = payload.get("data") if isinstance(payload, dict) else payload
    if not isinstance(entries, list):
        raise SetupError(tr("В каталоге WORKERHUB нет списка моделей.", "The WORKERHUB catalog does not contain a model list."))
    identifiers = {
        entry["id"]
        for entry in entries
        if isinstance(entry, dict)
        and isinstance(entry.get("id"), str)
        and MODEL_ID_PATTERN.fullmatch(entry["id"])
    }
    return sorted(identifiers)


def preferred_models(identifiers: list[str], family: str) -> list[str]:
    if family == "claude":
        selected = [item for item in identifiers if CLAUDE_PATTERN.search(item) and not re.search(r"image|audio|embed", item, re.I)]
    else:
        selected = [item for item in identifiers if CODEX_PATTERN.search(item) and not EXCLUDED_CODEX_PATTERN.search(item)]
    preferred = "sonnet" if family == "claude" else "sol"
    return sorted(set(selected), key=lambda item: (preferred not in item.lower(), item.casefold()))


def codex_catalog(available_ids: list[str], official_payload: dict | list) -> dict:
    official_models = official_payload.get("models") if isinstance(official_payload, dict) else None
    if not isinstance(official_models, list):
        raise SetupError(tr("Не удалось прочитать официальный каталог моделей Codex.", "Could not read the official Codex model catalog."))
    by_slug = {
        entry.get("slug"): entry
        for entry in official_models
        if isinstance(entry, dict) and isinstance(entry.get("slug"), str)
    }
    result = []
    for identifier in available_ids:
        entry = by_slug.get(identifier)
        if entry is None:
            continue
        model = copy.deepcopy(entry)
        if not model.get("base_instructions"):
            messages = model.get("model_messages")
            template = messages.get("instructions_template") if isinstance(messages, dict) else None
            model["base_instructions"] = template
        if not isinstance(model.get("base_instructions"), str) or not model["base_instructions"].strip():
            raise SetupError(tr("В метаданных Codex отсутствуют инструкции для одной из моделей. Настройки не изменены.", "Codex metadata is missing instructions for a model. No settings were changed."))
        model["visibility"] = "list"
        model["supported_in_api"] = True
        model["priority"] = len(result)
        model["use_responses_lite"] = False
        model["prefer_websockets"] = False
        model["supports_reasoning_effort_updates"] = False
        result.append(model)
    if not result:
        raise SetupError(tr("Нет моделей WORKERHUB, совместимых с текущим каталогом Codex.", "No WORKERHUB models are compatible with the current Codex catalog."))
    return {"models": result}


def parse_table_path(line: str) -> list[str] | None:
    match = re.match(r"^\s*(\[\[?)(.*?)(\]\]?)\s*(?:#.*)?$", line)
    if not match:
        return None
    opening, body, closing = match.groups()
    if (opening == "[[" and closing != "]]" ) or (opening == "[" and closing != "]"):
        return None
    parts = []
    index = 0
    while index < len(body):
        while index < len(body) and body[index].isspace():
            index += 1
        if index >= len(body):
            break
        if body[index] in "\"'":
            quote = body[index]
            end = index + 1
            value = []
            while end < len(body) and body[end] != quote:
                if body[end] == "\\" and quote == '"' and end + 1 < len(body):
                    end += 1
                value.append(body[end])
                end += 1
            if end >= len(body):
                return None
            parts.append("".join(value))
            index = end + 1
        else:
            end = index
            while end < len(body) and body[end] not in ". \t":
                end += 1
            token = body[index:end]
            if not token or not re.fullmatch(r"[A-Za-z0-9_-]+", token):
                return None
            parts.append(token)
            index = end
        while index < len(body) and body[index].isspace():
            index += 1
        if index < len(body):
            if body[index] != ".":
                return None
            index += 1
    return parts or None


def update_codex_config(original: str, model: str, catalog_path: Path, key_path: Path) -> str:
    invalid_config = tr("Не удалось безопасно обновить config.toml. Файл не изменён.", "Could not safely update config.toml. The file was not changed.")
    try:
        original_values = tomllib.loads(original)
    except tomllib.TOMLDecodeError as exc:
        raise SetupError(invalid_config) from exc
    if '"""' in original or "'''" in original or re.search(r"(?m)^\s*model_providers\s*(?:=|\.)", original):
        raise SetupError(tr("В config.toml есть неподдерживаемый синтаксис. Файл не изменён; настройте Codex вручную.", "config.toml uses unsupported syntax. The file was not changed; configure Codex manually."))

    kept = []
    section: list[str] = []
    drop_provider = False
    for line in original.splitlines():
        if line.lstrip().startswith("["):
            parsed = parse_table_path(line)
            if parsed is None:
                raise SetupError(tr("Не удалось безопасно прочитать раздел config.toml. Файл не изменён.", "Could not safely read a config.toml section. The file was not changed."))
            section = parsed
            drop_provider = len(section) >= 2 and section[:2] == ["model_providers", "workerhub"]
        if drop_provider:
            continue
        if len(section) == 1 and section[0] == "model_providers" and re.match(r"^\s*['\"]?workerhub['\"]?\s*=", line):
            raise SetupError(tr("В config.toml найден встроенный провайдер WORKERHUB. Файл не изменён.", "An inline WORKERHUB provider was found in config.toml. The file was not changed."))
        if not section and re.match(r"^\s*['\"]?(?:model|model_provider|model_catalog_json)['\"]?\s*=", line):
            allowed = re.match(
                r"^\s*(?:model|model_provider|model_catalog_json)\s*=\s*(?:\"(?:[^\"\\]|\\.)*\"|'[^']*')\s*(?:#.*)?$",
                line,
            )
            if not allowed:
                raise SetupError(tr("Настройка модели в config.toml использует сложный синтаксис. Файл не изменён.", "A model setting in config.toml uses complex syntax. The file was not changed."))
            continue
        kept.append(line)

    prefix = [
        f"model = {toml_quote(model)}",
        'model_provider = "workerhub"',
        f"model_catalog_json = {toml_quote(str(catalog_path))}",
        "",
    ]
    provider = [
        "[model_providers.workerhub]",
        'name = "WORKERHUB"',
        f"base_url = {toml_quote(API_BASE)}",
        'wire_api = "responses"',
        "supports_websockets = false",
        "",
        "[model_providers.workerhub.auth]",
        'command = "/bin/cat"',
        f"args = [{toml_quote(str(key_path))}]",
        "timeout_ms = 5000",
        "refresh_interval_ms = 0",
    ]
    body = "\n".join(kept).strip("\n")
    suffix = "\n".join(provider)
    updated = "\n\n".join(part for part in ("\n".join(prefix).rstrip("\n"), body, suffix) if part) + "\n"

    def unrelated(values: dict) -> dict:
        for key in ("model", "model_provider", "model_catalog_json"):
            values.pop(key, None)
        providers = values.get("model_providers")
        if isinstance(providers, dict):
            providers.pop("workerhub", None)
            if not providers:
                values.pop("model_providers")
        return values

    try:
        if unrelated(tomllib.loads(updated)) != unrelated(original_values):
            raise SetupError(invalid_config)
    except tomllib.TOMLDecodeError as exc:
        raise SetupError(invalid_config) from exc
    return updated


def toml_quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False).replace("\x7f", r"\u007f")


def json_change(path: Path, update: Callable[[dict], dict], mode: int = 0o600) -> Change:
    before, before_mode = snapshot(path)
    try:
        document = json.loads(before.decode("utf-8-sig")) if before else {}
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise SetupError(tr(f"Не удалось прочитать JSON-файл {path}.", f"Could not read JSON file {path}.")) from exc
    if not isinstance(document, dict):
        raise SetupError(tr(f"Ожидался JSON-объект в {path}. Настройки не изменены.", f"Expected a JSON object in {path}. No settings were changed."))
    updated = update(document)
    return Change(path, before, (json.dumps(updated, ensure_ascii=False, indent=2) + "\n").encode("utf-8"), before_mode, mode)


def reject_symlink_components(path: Path) -> None:
    absolute = path.absolute()
    for component in (absolute, *absolute.parents):
        if component.is_symlink():
            raise SetupError(tr(
                f"Путь {component} является символической ссылкой. Настройки не изменены.",
                f"Path {component} is a symbolic link. No settings were changed.",
            ))


def snapshot(path: Path) -> tuple[bytes | None, int | None]:
    reject_symlink_components(path)
    if not path.exists():
        return None, None
    if not path.is_file():
        raise SetupError(tr(f"{path} не является обычным файлом. Настройки не изменены.", f"{path} is not a regular file. No settings were changed."))
    try:
        info = path.stat()
        return path.read_bytes(), stat.S_IMODE(info.st_mode)
    except OSError as exc:
        raise SetupError(tr(f"Не удалось прочитать {path}. Настройки не изменены.", f"Could not read {path}. No settings were changed.")) from exc


def make_changes(target: str, key: str, model: str, models: list[str], catalog: dict | None, home: Path, codex_home: Path) -> list[Change]:
    changes = []
    if target == "Claude Desktop":
        support = home / "Library" / "Application Support"
        ordered = [model] + [item for item in models if item != model]
        profile = {
            "inferenceProvider": "gateway",
            "inferenceGatewayBaseUrl": CLAUDE_BASE,
            "inferenceGatewayAuthScheme": "bearer",
            "inferenceGatewayApiKey": key,
            "inferenceModels": ordered,
        }
        changes.append(json_change(support / "Claude" / "claude_desktop_config.json", lambda data: {**data, "deploymentMode": "3p"}))
        changes.append(json_change(support / "Claude-3p" / "claude_desktop_config.json", lambda data: {**data, "deploymentMode": "3p"}))
        profile_path = support / "Claude-3p" / "configLibrary" / f"{PROFILE_ID}.json"
        changes.append(json_change(profile_path, lambda data: {**data, **profile}))
        meta_path = support / "Claude-3p" / "configLibrary" / "_meta.json"

        def update_meta(data: dict) -> dict:
            entries = data.get("entries", [])
            if not isinstance(entries, list) or any(not isinstance(item, dict) for item in entries):
                raise SetupError(tr("Список профилей Claude Desktop повреждён. Настройки не изменены.", "The Claude Desktop profile list is invalid. No settings were changed."))
            data["entries"] = [item for item in entries if item.get("id") != PROFILE_ID] + [{"id": PROFILE_ID, "name": "WORKERHUB"}]
            data["appliedId"] = PROFILE_ID
            return data

        changes.append(json_change(meta_path, update_meta))
    elif target == "Claude Code CLI":
        settings_path = config_home(home, "CLAUDE_CONFIG_DIR", ".claude") / "settings.json"
        values = {
            "ANTHROPIC_BASE_URL": CLAUDE_BASE,
            "ANTHROPIC_AUTH_TOKEN": key,
            "ANTHROPIC_API_KEY": "",
            "ANTHROPIC_MODEL": model,
            "CLAUDE_CODE_USE_BEDROCK": "0",
            "CLAUDE_CODE_USE_VERTEX": "0",
            "CLAUDE_CODE_USE_FOUNDRY": "0",
        }
        for family in ("SONNET", "OPUS", "HAIKU", "FABLE"):
            alias = next((item for item in models if family.lower() in item.lower()), model)
            values[f"ANTHROPIC_DEFAULT_{family}_MODEL"] = alias
        values["CLAUDE_CODE_SUBAGENT_MODEL"] = values["ANTHROPIC_DEFAULT_SONNET_MODEL"]
        values["ANTHROPIC_SMALL_FAST_MODEL"] = values["ANTHROPIC_DEFAULT_HAIKU_MODEL"]

        def update_settings(data: dict) -> dict:
            env = data.get("env", {})
            if not isinstance(env, dict):
                raise SetupError(tr("Поле env в Claude Code settings.json имеет неверный формат. Настройки не изменены.", "The env field in Claude Code settings.json has an invalid format. No settings were changed."))
            data["env"] = {**env, **values}
            return data

        changes.append(json_change(settings_path, update_settings))
    else:
        if catalog is None:
            raise SetupError(tr("Для Codex не загружен каталог моделей.", "The Codex model catalog was not loaded."))
        workerhub_dir = home / ".workerhub"
        key_path = workerhub_dir / "api-key"
        catalog_path = codex_home / "workerhub-models.json"
        config_path = codex_home / "config.toml"
        before, before_mode = snapshot(key_path)
        changes.append(Change(key_path, before, (key + "\n").encode("utf-8"), before_mode, 0o600))
        before, before_mode = snapshot(catalog_path)
        catalog_bytes = (json.dumps(catalog, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
        changes.append(Change(catalog_path, before, catalog_bytes, before_mode, 0o600 if before is None else before_mode or 0o600))
        before, before_mode = snapshot(config_path)
        original = (before or b"").decode("utf-8-sig")
        updated = update_codex_config(original, model, catalog_path, key_path)
        changes.append(Change(config_path, before, updated.encode("utf-8"), before_mode, 0o600 if before is None else before_mode or 0o600))
    return [change for change in changes if change.before != change.after or change.before_mode != change.after_mode]


def ensure_parent(path: Path, secure: bool = False) -> None:
    reject_symlink_components(path.parent)
    missing = []
    current = path.parent
    while not current.exists():
        missing.append(current)
        current = current.parent
    if current.is_symlink():
        raise SetupError(tr(f"Родительский каталог {current} является символической ссылкой. Настройки не изменены.", f"Parent directory {current} is a symbolic link. No settings were changed."))
    for directory in reversed(missing):
        directory.mkdir(mode=0o700)
    if secure and os.name == "posix":
        info = path.parent.stat()
        if info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) & 0o022:
            raise SetupError(tr(f"Небезопасные права каталога {path.parent}.", f"Unsafe permissions on {path.parent}."))


def atomic_write(path: Path, data: bytes, mode: int) -> None:
    ensure_parent(path, secure=path.parent.name == ".workerhub")
    fd, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.workerhub-", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "wb") as stream:
            if hasattr(os, "fchmod"):
                os.fchmod(stream.fileno(), mode)
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def make_backup(change: Change) -> Path | None:
    if change.before is None:
        return None
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    backup = change.path.with_name(f"{change.path.name}.workerhub-{stamp}-{uuid.uuid4().hex[:8]}.bak")
    fd = os.open(backup, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "wb") as stream:
        stream.write(change.before)
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(backup, 0o600)
    return backup


def commit_changes(changes: list[Change]) -> list[Path]:
    for change in changes:
        current, current_mode = snapshot(change.path)
        if current != change.before or (current is not None and current_mode != change.before_mode):
            raise SetupError(tr(f"{change.path} изменилась во время настройки. Повторите запуск.", f"{change.path} changed during setup. Run the installer again."))

    backups: list[Path] = []
    committed: list[Change] = []
    try:
        for change in changes:
            backup = make_backup(change)
            if backup is not None:
                backups.append(backup)
            atomic_write(change.path, change.after, change.after_mode)
            committed.append(change)
    except (Exception, KeyboardInterrupt) as exc:
        rollback_error = None
        for change in reversed(committed):
            try:
                if change.before is None:
                    change.path.unlink(missing_ok=True)
                else:
                    atomic_write(change.path, change.before, change.before_mode if change.before_mode is not None else 0o600)
            except Exception as rollback_exc:
                rollback_error = rollback_exc
        if rollback_error is not None:
            raise SetupError(tr("Не удалось полностью вернуть настройки. Резервные копии .workerhub-*.bak сохранены.", "Could not fully restore settings. The .workerhub-*.bak backups were kept.")) from rollback_error
        if isinstance(exc, SetupError):
            raise
        raise SetupError(tr("Не удалось сохранить настройки. Изменения отменены; повторите запуск.", "Could not save settings. Changes were rolled back; try again.")) from exc
    return backups


def config_home(home: Path, env: str, default: str) -> Path:
    configured = os.environ.get(env)
    if not configured:
        return home / default
    path = Path(configured).expanduser()
    return path if path.is_absolute() else home / path


def language_menu() -> str:
    return "en" if choose("Language / Язык", ["English", "Русский"]) == 0 else "ru"


def configure() -> int:
    global LANGUAGE
    language = language_menu()
    LANGUAGE = language
    targets = ["Claude Desktop", "Claude Code CLI", "Codex", "Codex CLI"]
    target = targets[choose(text(language, "Что подключить?", "What would you like to connect?"), targets)]
    family = "claude" if target.startswith("Claude") else "codex"
    home = Path.home().resolve()
    api_payload = fetch_json(API_BASE + "/models")
    all_ids = model_ids(api_payload)
    models = preferred_models(all_ids, family)
    if target == "Claude Desktop":
        models = [item for item in models if DESKTOP_MODEL_PATTERN.match(item)][:200]
    if not models:
        raise SetupError(text(language, "Подходящие текстовые модели не найдены.", "No compatible text models are available."))
    catalog = None
    if family == "codex":
        catalog = codex_catalog(models, fetch_json(CODEX_MODELS_URL))
        models = [entry["slug"] for entry in catalog["models"]]
    key = read_key()
    model = models[choose(text(language, "Модель", "Model"), models)]
    codex_home = config_home(home, "CODEX_HOME", ".codex")
    changes = make_changes(target, key, model, models, catalog, home, codex_home)
    key = ""
    if not changes:
        print(text(language, "Подключение уже настроено. Файлы не изменились.", "This connection is already configured. No files changed."))
        return 0
    commit_changes(changes)
    print(tr("\nГотово. Полностью перезапустите приложение.", "\nDone. Fully restart the app."))
    return 0


def main() -> int:
    if sys.argv[1:] == ["--help"]:
        print("WORKERHUB Connect · macOS\nUsage: sh workerhub-macos.command\nRequires Python 3.11+ and Terminal.")
        return 0
    if sys.platform != "darwin":
        print("This WORKERHUB Connect file runs on macOS only.", file=sys.stderr)
        return 2
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        print("Open Terminal and run this file there.", file=sys.stderr)
        return 2
    print("WORKERHUB Connect · macOS")
    try:
        return configure()
    except (KeyboardInterrupt, EOFError):
        print(tr("\nНастройка отменена.", "\nSetup cancelled."), file=sys.stderr)
        return 1
    except SetupError as exc:
        print(f"\n{exc}", file=sys.stderr)
        return 1
    except (OSError, ValueError):
        print(tr("\nНе удалось прочитать настройки.", "\nCould not read the settings."), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
# WORKERHUB_PYTHON_END
