import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from unittest.mock import patch

from tek.app.app_paths import AppPaths
from tek.app.settings_store import SettingsStore
from tek.project_identity import PROJECT_ID, APP_TITLE

ROOT = Path(__file__).resolve().parents[1]


def test_standalone_structure_and_savedvariables():
    assert not (ROOT / "addon/!TacticEcho").exists()
    assert not (ROOT / "scripts/package-tek-release.ps1").exists()
    assert not (ROOT / ".gitmodules").exists()
    toc = (ROOT / "Tactic Echo Forever/Tactic Echo Forever.toc").read_text(encoding="utf-8")
    assert "## SavedVariables: TEF_DB" in toc
    assert (ROOT / "VERSION").read_text(encoding="utf-8").strip() == "1.0.15"
    assert PROJECT_ID == "TEF" and "TEF" in APP_TITLE


def test_settings_migration_preserves_legacy_and_is_idempotent():
    with tempfile.TemporaryDirectory() as temporary:
        base = Path(temporary)
        legacy = base / "TacticEcho"
        (legacy / "config").mkdir(parents=True)
        (legacy / "profiles").mkdir()
        old = {"auto_start_ui_linked": True, "sampling_interval_ms": 77,
               "signal_layout_cache": {"x": 12}, "wow_savedvariables_path": "old.lua"}
        original = json.dumps(old).encode()
        (legacy / "config/settings.json").write_bytes(original)
        (legacy / "profiles/custom.json").write_text('{"profileId":"custom"}')
        with patch.dict(os.environ, {"LOCALAPPDATA": temporary}):
            paths = AppPaths.from_environment()
            assert paths.root == base / "TacticEchoForever"
            paths.ensure()
        migrated = SettingsStore(paths.settings_json).load()
        assert migrated.sampling_interval_ms == 77
        assert not migrated.auto_start_ui_linked
        assert migrated.signal_layout_cache is None
        assert migrated.wow_savedvariables_path == ""
        assert (legacy / "config/settings.json").read_bytes() == original
        assert (paths.config / "legacy-settings-before-split.json").read_bytes() == original
        assert (paths.profiles / "custom.json").is_file()
        paths.settings_json.write_text('{"sampling_interval_ms":99}')
        paths.ensure()
        assert SettingsStore(paths.settings_json).load().sampling_interval_ms == 99
        assert (legacy / "config/settings.json").read_bytes() == original


def test_relocated_copy_runs_without_original_or_sibling_checkout():
    with tempfile.TemporaryDirectory() as temporary:
        standalone = Path(temporary) / "independent"
        standalone.mkdir()
        for name in ["Tactic Echo Forever", "tek", "examples", "docs", "scripts"]:
            shutil.copytree(ROOT / name, standalone / name,
                            ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
        for name in ["VERSION", "README.md", "AGENTS.md", "CHANGELOG.md"]:
            shutil.copy2(ROOT / name, standalone / name)
        env = os.environ.copy()
        env.pop("PYTHONPATH", None)
        for command in [
            [sys.executable, "scripts/verify-baseline-contract.py", "--repo-root", "."],
            [sys.executable, "Tactic Echo Forever/tests/run.py"],
        ]:
            completed = subprocess.run(command, cwd=standalone, env=env,
                                       capture_output=True, text=True)
            assert completed.returncode == 0, completed.stdout + completed.stderr
