# Tactic Echo Forever

Independent local project for World of Warcraft: Forever / Infinite, a
Classic-60-style Class + Talent + Learned Skills system, APL, Secret Value,
TEAP and TEF TEK.

Originally derived from Tactic Echo. From source commit
`3e57b9d1713ad3c9d821b416dc073452289c2691` on 2026-10-12 onward, TEF is developed
independently. This is not a Tactic Echo submodule; no sibling checkout is
required. Project version remains **1.0.1**.

- AddOn: `TACTIC-ECHO-FOREVER/`; SavedVariables: `TEF_DB`.
- TEF TEK: `tek/`; config/log/cache root: `%LOCALAPPDATA%/TacticEchoForever`.
- First-start migration copies legacy settings and profiles without writing or
  removing old data. Original settings are backed up locally; activation and
  signal-layout hints are reset for explicit confirmation in the new project.
- TEAP namespace: **TEF**. Existing v3 wire format is unchanged and cannot
  distinguish the project on wire. Enable only one AddOn signal source at a time.
- TEF TEK evolves independently of Retail TE TEK; no automatic synchronization.

## Local checks

```powershell
python scripts/verify-baseline-contract.py --repo-root .
python TACTIC-ECHO-FOREVER/tests/run.py
python -m pytest -q tek/tests tests
python -m unittest discover -s tek/tests -q
python -m unittest discover -s TACTIC-ECHO-FOREVER/tests -q
python -m compileall -q tek/src tek/app tek/runtime
```

Lua simulation requires `lupa` (Lua 5.1). Windows build dependencies are in
`requirements-windows.txt`. Build TEF TEK with
`pwsh -File scripts/build-tek-exe.ps1 -OutputDirectory dist/standalone-build -SkipSmokeTest`.
Output is `TEK-TEF.exe`; a build is not real input acceptance.
Package AddOn source with `python TACTIC-ECHO-FOREVER/scripts/deliver.py`.
Full source and Windows release packaging are separate; see
`scripts/package-tef-release.py --help`.

[Split metadata](docs/PROJECT_SPLIT.md) ·
[Current APL contract](TACTIC-ECHO-FOREVER/docs/APL_FOUNDATION_FIX_1.0.1.md)
