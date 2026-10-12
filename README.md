# Tactic Echo Forever

Independent local project for World of Warcraft: Forever / Infinite, a
Classic-60-style Class + Talent + Learned Skills system, APL, Secret Value,
TEAP and TEF TEK.

Originally derived from Tactic Echo. From source commit
`3e57b9d1713ad3c9d821b416dc073452289c2691` on 2026-10-12 onward, TEF is developed
independently. This is not a Tactic Echo submodule; no sibling checkout is
required. Current project version is **1.0.13**.

- AddOn: `Tactic Echo Forever/`; SavedVariables: `TEF_DB`.
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
python "Tactic Echo Forever/tests/run.py"
python -m pytest -q tek/tests tests
python -m unittest discover -s tek/tests -q
python -m unittest discover -s "Tactic Echo Forever/tests" -q
python -m compileall -q tek/src tek/app tek/runtime
```

Lua simulation requires `lupa` (Lua 5.1). Windows build dependencies are in
`requirements-windows.txt`. Build TEF TEK with
`pwsh -File scripts/build-tek-exe.ps1 -OutputDirectory dist/standalone-build -SkipSmokeTest`.
Output is `TEK-TEF.exe`; a build is not real input acceptance.
Package AddOn source with `python "Tactic Echo Forever/scripts/deliver.py"`.
Full source and Windows release packaging are separate; see
`scripts/package-tef-release.py --help`.

[Split metadata](docs/PROJECT_SPLIT.md) ·
[Current APL contract](<Tactic Echo Forever/docs/APL_FOUNDATION_FIX_1.0.1.md>)

AddOn directory and TOC are both named `Tactic Echo Forever`. When replacing an
older installation, keep only one TEF AddOn enabled. The game saves `TEF_DB`
under the new AddOn filename; existing old-name data is not migrated by this rename.

Experimental cast-tail queue: enable “读条末尾提前排队（实验）” on the TEK settings page, close settings, then start dispatch. It is off by default and only supports fixed-sequence ordinary casts, including repeats. No APL/channel/Shoot or loop-boundary prediction; unknown timing stays blocked. The lead is capped by the public client SpellQueueWindow. Queue acceptance must be verified in game.

Manual sequence rows offer “不可用跳过”, default off; save after editing. It skips the remaining repeats only on public unavailability, never UNKNOWN or a pending cast. Advanced text example: `205:205*3!skip`. Own cooldown must be publicly distinguishable from GCD; otherwise the step waits.

Settings now use manual sequence or custom APL only. Loop/reset lives in dispatch overview; label styles live in HUD appearance. Both merged pages scroll. Legacy code mode uses saved manual rows; built-in APL is disabled on migration, while custom rules are preserved.

提前排队时间滑块范围0–0.5秒，步进0.05秒，默认0.20秒；0不提前。实际窗口取配置值与公开客户端SpellQueueWindow的较小值。修改会停止派发，关闭设置后需重新开启。

排队诊断独立保存在TEF_DB.queueDiagnostics（最多512条），淘汰数queueEvicted；保存公开时间、GUID、事件与请求/回执关联。TOKEN_PUBLISHED只证明插件发布，不证明桌面输入；remaining是发起排队时的快照。记录不改变派发逻辑。
