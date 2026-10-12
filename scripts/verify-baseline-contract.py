"""Standalone TEF repository/archive contracts; no Retail checkout dependency."""
import argparse
from pathlib import Path, PurePosixPath
import zipfile

FORBIDDEN = {".git", "build", "dist", "release", "logs", "__pycache__", ".pytest_cache", "WTF", "SavedVariables"}
def verify_repository(root):
    addon = root / "Tactic Echo Forever"
    version = (root / "VERSION").read_text().strip()
    assert (addon / "VERSION").read_text().strip() == version
    toc = (addon / "Tactic Echo Forever.toc").read_text(encoding="utf-8")
    assert "## Version: " + version in toc and "## SavedVariables: TEF_DB" in toc
    assert 'local VERSION = "' + version + '"' in (addon / "Core/Bootstrap.lua").read_text(encoding="utf-8")
    assert 'TEF.Version = "' + version + '"' in (addon / "Config.lua").read_text(encoding="utf-8")
    entries = [line.strip() for line in toc.splitlines() if line.strip() and not line.startswith("#")]
    assert "Bindings.xml" not in entries
    for name in entries + ["Bindings.xml"]:
        assert (addon / name).is_file(), name
    for name in ["README.md", "AGENTS.md", "CHANGELOG.md", "docs/PROJECT_SPLIT.md", "tek/app/main.py", "tek/src/teap.py"]:
        assert (root / name).is_file(), name
    assert (root / "docs/baselines/tef" / ("BASELINE_" + version + ".md")).is_file()
    assert not (root / "addon/!TacticEcho").exists()
    assert not (root / "tests/unit").exists()
    assert not (root / "scripts/package-tek-release.ps1").exists()
    assert not (root / ".gitmodules").exists()
    for parent in [addon, root / "tek", root / "scripts"]:
        for p in parent.rglob("*"):
            assert not p.is_symlink(), p
    print("TEF standalone baseline contract passed.")

def verify_archive(path, expected_root, release=False):
    with zipfile.ZipFile(path) as z:
        names = z.namelist()
        assert {n.split("/")[0] for n in names} == {expected_root}
        for name in names:
            p = PurePosixPath(name)
            assert not p.is_absolute() and ".." not in p.parts
            assert not (set(p.parts) & FORBIDDEN), name
            assert p.suffix not in {".pyc", ".log", ".jsonl", ".zip"}, name
            assert p.suffix != ".exe" or release, name
        assert expected_root + "/Tactic Echo Forever/Tactic Echo Forever.toc" in names
        assert not any("/addon/!TacticEcho/" in name for name in names)
    print("TEF standalone archive contract passed.")

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repo-root", type=Path)
    parser.add_argument("--archive", type=Path)
    parser.add_argument("--expect-root")
    parser.add_argument("--release-package", action="store_true")
    args = parser.parse_args()
    if args.repo_root: verify_repository(args.repo_root.resolve())
    if args.archive: verify_archive(args.archive, args.expect_root, args.release_package)
    if not args.repo_root and not args.archive: parser.error("select repository or archive")
if __name__ == "__main__": main()
