from __future__ import annotations

import importlib.util
import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


COMMAND = Path(__file__).resolve().parents[1] / "workerhub-macos.command"
TEXT = COMMAND.read_text(encoding="utf-8")
START = "<<'WORKERHUB_PYTHON_PAYLOAD'\n"
END = '\nWORKERHUB_PYTHON_PAYLOAD\n)"'
PAYLOAD = TEXT.split(START, 1)[1].split(END, 1)[0]
SPEC = importlib.util.spec_from_loader("workerhub_macos_payload", loader=None)
macos = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = macos
exec(compile(PAYLOAD, str(COMMAND), "exec"), macos.__dict__)


class MacOSInstallerTests(unittest.TestCase):
    def test_command_is_single_file_and_shell_wrapper_is_well_formed(self):
        self.assertTrue(TEXT.startswith("#!/bin/sh\n"))
        self.assertEqual(TEXT.count("\nWORKERHUB_PYTHON_PAYLOAD\n"), 1)
        self.assertIn("Python 3.11", TEXT)
        self.assertIn("os.read(fd, 1)", PAYLOAD)

    def test_menu_reader_handles_macos_and_ansi_arrow_sequences(self):
        sequences = [
            ([b"\x1b", b"[", b"A"], "up"),
            ([b"\x1b", b"[", b"B"], "down"),
            ([b"\x1b", b"O", b"A"], "up"),
            ([b"\x1b", b"O", b"B"], "down"),
            ([b"\r"], "enter"),
            ([b"\x03"], "cancel"),
            ([b"\x04"], "cancel"),
        ]
        for input_bytes, expected in sequences:
            reads = iter(input_bytes)
            with self.subTest(input_bytes=input_bytes), patch.object(macos.os, "read", side_effect=lambda _fd, _size: next(reads)), patch("select.select", return_value=([7], [], [])):
                self.assertEqual(macos.read_menu_key(7), expected)

    def test_choose_moves_selection_and_restores_terminal_mode(self):
        if not hasattr(os, "openpty"):
            self.skipTest("Pseudo-terminals are unavailable")
        import io
        import termios

        master, slave = os.openpty()
        original_stdin, original_stdout = macos.sys.stdin, macos.sys.stdout

        class TTYBuffer(io.StringIO):
            def isatty(self):
                return True

        input_stream = os.fdopen(os.dup(slave), "r", encoding="utf-8")
        output_stream = TTYBuffer()
        before = termios.tcgetattr(slave)
        try:
            macos.sys.stdin = input_stream
            macos.sys.stdout = output_stream
            with patch.object(macos, "read_menu_key", side_effect=["down", "enter"]):
                self.assertEqual(macos.choose("Choose", ["one", "two"]), 1)
            self.assertEqual(termios.tcgetattr(slave), before)
        finally:
            macos.sys.stdin, macos.sys.stdout = original_stdin, original_stdout
            input_stream.close()
            os.close(master)
            os.close(slave)

    def test_menu_reader_treats_escape_timeout_as_cancel(self):
        with patch.object(macos.os, "read", return_value=b"\x1b"), patch("select.select", return_value=([], [], [])):
            self.assertEqual(macos.read_menu_key(7), "cancel")

    def test_language_menu_maps_english_first_and_russian_second(self):
        with patch.object(macos, "choose", side_effect=[0, 1]):
            self.assertEqual(macos.language_menu(), "en")
            self.assertEqual(macos.language_menu(), "ru")

    def test_model_filter_keeps_only_matching_text_models(self):
        payload = {
            "data": [
                {"id": "claude-sonnet-5-5"},
                {"id": "claude-opus-5-5"},
                {"id": "claude-image-2"},
                {"id": "gpt-6.2-astra"},
                {"id": "gpt-image-2.6"},
                {"id": "gemini-4-carbon"},
                {"id": "invalid model"},
            ]
        }
        ids = macos.model_ids(payload)
        self.assertEqual(macos.preferred_models(ids, "claude"), ["claude-sonnet-5-5", "claude-opus-5-5"])
        self.assertEqual(macos.preferred_models(ids, "codex"), ["gpt-6.2-astra"])

    def test_codex_catalog_uses_official_metadata_without_unmatched_models(self):
        official = {
            "models": [
                {"slug": "gpt-6.2-astra", "model_messages": {"instructions_template": "Follow the default instructions."}},
                {"slug": "gpt-image-2.6", "base_instructions": "Image instructions."},
            ]
        }
        catalog = macos.codex_catalog(["gpt-6.2-astra", "gpt-image-2.6", "missing"], official)
        self.assertEqual([item["slug"] for item in catalog["models"]], ["gpt-6.2-astra", "gpt-image-2.6"])
        entry = catalog["models"][0]
        self.assertEqual(entry["base_instructions"], "Follow the default instructions.")
        self.assertTrue(entry["supported_in_api"])
        self.assertFalse(entry["supports_reasoning_effort_updates"])

    def test_codex_config_merges_idempotently_and_preserves_other_settings(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            catalog = root / "workerhub-models.json"
            key = root / "with spaces" / "api-key"
            original = '''approval_policy = "on-request"
model = "old-model"
model_provider = "previous"
[projects.'c:\\users\\sample\\project.with.dots']
trust_level = "trusted"
[model_providers.previous]
name = "Keep me"
base_url = "https://example.invalid/v1"
[model_providers.workerhub]
name = "Old WORKERHUB"
[model_providers.workerhub.auth]
command = "old-helper"
'''
            updated = macos.update_codex_config(original, "gpt-6.2-astra", catalog, key)
            self.assertIn('approval_policy = "on-request"', updated)
            self.assertIn("[projects.'c:\\users\\sample\\project.with.dots']", updated)
            self.assertIn('name = "Keep me"', updated)
            self.assertIn('model = "gpt-6.2-astra"', updated)
            auth = macos.tomllib.loads(updated)["model_providers"]["workerhub"]["auth"]
            self.assertEqual(auth["command"], "/bin/cat")
            self.assertEqual(auth["args"], [str(key)])
            self.assertEqual(updated, macos.update_codex_config(updated, "gpt-6.2-astra", catalog, key))

    def test_codex_config_refuses_unsafe_inline_toml(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            with self.assertRaises(macos.SetupError):
                macos.update_codex_config('model_providers = { other = {} }', "gpt-6.2-astra", root / "models.json", root / "token")
            with self.assertRaises(macos.SetupError):
                macos.update_codex_config('model = [\n  "old",\n]', "gpt-6.2-astra", root / "models.json", root / "token")

    def test_claude_code_keeps_existing_settings_and_escapes_no_secrets_to_output(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory).resolve()
            settings = home / ".claude" / "settings.json"
            settings.parent.mkdir()
            settings.write_text(json.dumps({"theme": "dark", "env": {"CUSTOM_VAR": "kept", "ANTHROPIC_API_KEY": "old"}}), encoding="utf-8")
            changes = macos.make_changes("Claude Code CLI", "sk-workerhub-secret", "claude-sonnet-5-5", ["claude-sonnet-5-5", "claude-opus-5-5"], None, home, home / ".codex")
            self.assertEqual(len(changes), 1)
            updated = json.loads(changes[0].after)
            self.assertEqual(updated["theme"], "dark")
            self.assertEqual(updated["env"]["CUSTOM_VAR"], "kept")
            self.assertEqual(updated["env"]["ANTHROPIC_AUTH_TOKEN"], "sk-workerhub-secret")
            self.assertEqual(updated["env"]["ANTHROPIC_API_KEY"], "")
            self.assertEqual(changes[0].after_mode, 0o600)

    def test_claude_desktop_keeps_existing_profile_and_activates_workerhub(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory).resolve()
            support = home / "Library" / "Application Support"
            meta = support / "Claude-3p" / "configLibrary" / "_meta.json"
            meta.parent.mkdir(parents=True)
            meta.write_text(json.dumps({"entries": [{"id": "other", "name": "Existing"}], "unknown": True}), encoding="utf-8")
            changes = macos.make_changes("Claude Desktop", "sk-workerhub-secret", "claude-opus-5-5", ["claude-sonnet-5-5", "claude-opus-5-5"], None, home, home / ".codex")
            updated_meta = next(change for change in changes if change.path == meta)
            document = json.loads(updated_meta.after)
            self.assertTrue(document["unknown"])
            self.assertEqual(document["appliedId"], macos.PROFILE_ID)
            self.assertEqual(len(document["entries"]), 2)
            profile = next(change for change in changes if change.path.name == f"{macos.PROFILE_ID}.json")
            self.assertEqual(json.loads(profile.after)["inferenceModels"], ["claude-opus-5-5", "claude-sonnet-5-5"])

    def test_codex_key_stays_in_private_file(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory).resolve()
            catalog = {"models": [{"slug": "gpt-6.2-astra"}]}
            changes = macos.make_changes("Codex", "sk-workerhub-secret", "gpt-6.2-astra", ["gpt-6.2-astra"], catalog, home, home / ".codex")
            key_change = next(change for change in changes if change.path.name == "api-key")
            config_change = next(change for change in changes if change.path.name == "config.toml")
            self.assertEqual(key_change.after, b"sk-workerhub-secret\n")
            self.assertEqual(key_change.after_mode, 0o600)
            self.assertIn("[model_providers.workerhub.auth]", config_change.after.decode())
            self.assertNotIn("sk-workerhub-secret", config_change.after.decode())

    def test_snapshot_rejects_symlinked_target_and_parent(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            actual = root / "actual"
            actual.mkdir()
            target = actual / "settings.json"
            target.write_text("{}", encoding="utf-8")
            link = root / "linked-settings.json"
            parent_link = root / "linked-parent"
            try:
                link.symlink_to(target)
                parent_link.symlink_to(actual, target_is_directory=True)
            except (OSError, NotImplementedError):
                self.skipTest("Symbolic links are unavailable in this environment")
            with self.assertRaises(macos.SetupError):
                macos.snapshot(link)
            with self.assertRaises(macos.SetupError):
                macos.snapshot(parent_link / "settings.json")

    def test_codex_home_respects_absolute_and_home_relative_overrides(self):
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory).resolve() / "home"
            absolute = Path(directory).resolve() / "custom-codex"
            with patch.dict(os.environ, {"CODEX_HOME": str(absolute)}):
                self.assertEqual(macos.config_home(home, "CODEX_HOME", ".codex"), absolute)
            with patch.dict(os.environ, {"CODEX_HOME": "custom-codex"}):
                self.assertEqual(macos.config_home(home, "CODEX_HOME", ".codex"), home / "custom-codex")

    def test_commit_backs_up_and_rolls_back_failed_group(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            first = root / "settings.json"
            second = root / "nested" / "config.toml"
            first.write_bytes(b'{"old": true}\n')
            mode = stat.S_IMODE(first.stat().st_mode)
            first_change = macos.Change(first, first.read_bytes(), b'{"new": true}\n', mode, mode)
            second_change = macos.Change(second, None, b"new config\n", None, 0o600)
            real_atomic_write = macos.atomic_write
            calls = 0

            def fail_on_second(path, data, file_mode):
                nonlocal calls
                calls += 1
                if calls == 2:
                    raise OSError("injected write failure")
                real_atomic_write(path, data, file_mode)

            with patch.object(macos, "atomic_write", side_effect=fail_on_second):
                with self.assertRaises(macos.SetupError):
                    macos.commit_changes([first_change, second_change])
            self.assertEqual(first.read_bytes(), b'{"old": true}\n')
            self.assertFalse(second.exists())
            backup = next(root.glob("settings.json.workerhub-*.bak"))
            self.assertEqual(backup.read_bytes(), b'{"old": true}\n')
            if os.name == "posix":
                self.assertEqual(stat.S_IMODE(backup.stat().st_mode), 0o600)


if __name__ == "__main__":
    unittest.main()