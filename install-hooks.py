#!/usr/bin/env python3
"""Add the reminder hook without replacing any existing hooks or notify command."""
import argparse
import json
import os
from pathlib import Path
import shutil
import tempfile

root = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--config-dir", type=Path, help="Override the Codex configuration directory")
args = parser.parse_args()
config_dir = args.config_dir or Path(os.environ.get("CODEX_HOME", str(Path.home() / ".codex")))
target = config_dir / "hooks.json"
example = json.loads((root / "hooks.example.json").read_text())
hook = example["hooks"]["Stop"][0]["hooks"][0]
existing = json.loads(target.read_text()) if target.exists() else {"hooks": {}}
groups = existing.setdefault("hooks", {}).setdefault("Stop", [])
if not any(item.get("command") == hook["command"] for group in groups for item in group.get("hooks", [])):
    if target.exists():
        backup = target.with_name("hooks.json.before-dualsense")
        if not backup.exists():
            shutil.copy2(target, backup)
    groups.append({"hooks": [hook]})
    target.parent.mkdir(parents=True, exist_ok=True)
    fd, path = tempfile.mkstemp(prefix=".dualsense-hooks-", dir=target.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(existing, stream, ensure_ascii=False, indent=2)
            stream.write("\n")
        os.replace(path, target)
    finally:
        if os.path.exists(path):
            os.unlink(path)
print(f"Installed: {target}")
print("Review and trust this Stop hook in Codex before it can run. Existing notify is unchanged.")
