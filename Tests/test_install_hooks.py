"""Installer integration tests confined to disposable configuration directories."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallHooksTests(unittest.TestCase):
    def run_installer(self, directory):
        subprocess.run(
            [sys.executable, str(ROOT / "install-hooks.py"), "--config-dir", str(directory)],
            check=True, capture_output=True, text=True,
        )

    def test_new_config_and_idempotence(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp) / "config"
            self.run_installer(directory)
            target = directory / "hooks.json"
            before = target.read_bytes()
            data = json.loads(before)
            self.assertEqual(len(data["hooks"]["Stop"]), 1)
            self.assertIn("DualSenseNotify", data["hooks"]["Stop"][0]["hooks"][0]["command"])
            self.run_installer(directory)
            self.assertEqual(target.read_bytes(), before)
            self.assertFalse((directory / "hooks.json.before-dualsense").exists())

    def test_merge_preserves_existing_hooks_config_and_backup(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            original = {"metadata": "keep", "hooks": {
                "Stop": [{"hooks": [{"type": "command", "command": "existing-hook"}]}],
                "SessionStart": [{"hooks": [{"type": "command", "command": "startup-hook"}]}],
            }}
            target = directory / "hooks.json"
            target.write_text(json.dumps(original))
            original_bytes = target.read_bytes()
            config = directory / "config.toml"
            config.write_text('notify = ["existing-notifier"]\n')
            self.run_installer(directory)
            updated = json.loads(target.read_text())
            self.assertEqual(updated["metadata"], "keep")
            self.assertEqual(updated["hooks"]["Stop"][0], original["hooks"]["Stop"][0])
            self.assertEqual(updated["hooks"]["SessionStart"], original["hooks"]["SessionStart"])
            self.assertEqual(len(updated["hooks"]["Stop"]), 2)
            self.assertEqual((directory / "hooks.json.before-dualsense").read_bytes(), original_bytes)
            self.assertEqual(config.read_text(), 'notify = ["existing-notifier"]\n')
            self.run_installer(directory)
            self.assertEqual(len(json.loads(target.read_text())["hooks"]["Stop"]), 2)
            self.assertEqual((directory / "hooks.json.before-dualsense").read_bytes(), original_bytes)

    def test_invalid_json_is_left_untouched(self):
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp)
            target = directory / "hooks.json"
            target.write_text("invalid existing configuration")
            with self.assertRaises(subprocess.CalledProcessError):
                self.run_installer(directory)
            self.assertEqual(target.read_text(), "invalid existing configuration")


if __name__ == "__main__":
    unittest.main()
