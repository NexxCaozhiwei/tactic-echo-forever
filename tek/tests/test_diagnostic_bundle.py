from __future__ import annotations

import json
import tempfile
import unittest
import zipfile
from pathlib import Path

from tek.app.app_paths import AppPaths
from tek.app.settings_store import AppSettings, SettingsStore
from tek.runtime.runtime_status import TEKStatusSnapshot
from tek.src.diagnostic_bundle import create_diagnostic_bundle


class DiagnosticBundleTests(unittest.TestCase):
    def test_bundle_contains_only_tef_runtime_diagnostics(self):
        with tempfile.TemporaryDirectory() as temporary:
            paths = AppPaths.from_root(Path(temporary) / "state")
            paths.ensure()
            store = SettingsStore(paths.settings_json)
            store.save(AppSettings())
            paths.tray_log.write_text("tray sample\n", encoding="utf-8")
            paths.trace_path_for_today().write_text('{"trace":true}\n', encoding="utf-8")
            profile = paths.profiles / "laptop.json"
            profile.write_text(json.dumps({"profileId": "laptop"}), encoding="utf-8")
            snapshot = TEKStatusSnapshot.stopped(log_dir=str(paths.logs))

            bundle_path, manifest = create_diagnostic_bundle(
                paths=paths,
                settings_store=store,
                status_snapshot=snapshot,
            )

            self.assertTrue(bundle_path.exists())
            self.assertEqual(manifest["schemaVersion"], 3)
            self.assertNotIn("mappingExportIncluded", manifest)
            self.assertNotIn("mappingExportError", manifest)
            with zipfile.ZipFile(bundle_path) as archive:
                names = set(archive.namelist())
                self.assertIn("manifest.json", names)
                self.assertIn("settings.json", names)
                self.assertIn("status.json", names)
                self.assertIn("SUMMARY.md", names)
                self.assertNotIn("te-mapping-export.json", names)
                summary = archive.read("SUMMARY.md").decode("utf-8")
                self.assertIn("不读取或包含其他插件 SavedVariables", summary)

    def test_legacy_mapping_setting_is_not_exported(self):
        with tempfile.TemporaryDirectory() as temporary:
            paths = AppPaths.from_root(Path(temporary) / "state")
            paths.ensure()
            paths.settings_json.write_text(
                json.dumps({"schema_version": 8, "wow_savedvariables_path": "old.lua"}),
                encoding="utf-8",
            )
            store = SettingsStore(paths.settings_json)

            bundle_path, manifest = create_diagnostic_bundle(paths=paths, settings_store=store)

            self.assertNotIn("mappingExportIncluded", manifest)
            with zipfile.ZipFile(bundle_path) as archive:
                settings = json.loads(archive.read("settings.json"))
                self.assertNotIn("wow_savedvariables_path", settings)


if __name__ == "__main__":
    unittest.main()
