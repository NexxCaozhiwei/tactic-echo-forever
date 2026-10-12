# Local project split — 2026-10-12

- Split source commit: `3e57b9d1713ad3c9d821b416dc073452289c2691`.
- Original shared repository / Retail TE path: `G:\Desktop\CODES\tactic-echo`.
- New local sibling TEF path: `G:\Desktop\CODES\Tactic Echo Forever`.
- Rollback tag: `pre-te-tef-split` (source HEAD; dirty files preserved separately).
- Safety backup: `G:\Desktop\CODES\_project-split-backups\tactic-echo-20261012-084826`.
- Full backup verified: 1,310 files; 31 dirty/untracked source files overlaid in clone.
- Preserved local branches: codex/tef, main; prior tags retained, no history rewrite.

TE scope: Retail AddOn, HUD/main recommendation/special modes/AutoInjection,
its own TEK, Retail tests/tools/docs. Retired reaction modules stay retired.
TEF scope: Infinite/Forever, Classic60 class/talents/learned ranks, APL,
Secret Value, fixed sequence, its own TEK, TEF tests/tools/docs.

TEK was copied into both projects at the split point.
From this point forward, TE TEK and TEF TEK may evolve independently.
No automatic code synchronization, shared core, submodule, symlink or junction.
No runtime access to the other checkout. `source` is Git provenance only, has
no automatic push target and a disabled push URL. Original TE origin unchanged.

TEAP policy: logical namespaces TE and TEF. v3 wire stays unchanged; it does
not identify the project. One enabled AddOn signal source at a time. Build/
trace/status metadata distinguish TEF without modifying input authorization.

TEF host state: `%LOCALAPPDATA%/TacticEchoForever`; title TEF TEK, executable
TEK-TEF.exe. Settings/profile migration is read-only for the legacy directory,
backs up original settings, and resets activation/cache/SavedVariables import.
Retail host state remains `%LOCALAPPDATA%/TacticEcho`. No live host was stopped.

SavedVariables: Retail `TacticEchoDB`; TEF `TEF_DB`, unchanged and distinct.
Versions unchanged: TE 1.5.12, TEF 1.0.1. This task adds split metadata only.

Deletion inventories and classification are in split-file-classification.json.
TEF removed 370 confirmed Retail-only files from the clone.
TE removes 141 TEF-only source/doc/test/tool files only after
TEF loading, APL/Runtime/Dispatch/Transport and local TEK tests pass.
Inherited catalog/protocol/parser fixtures are local compatibility assets,
not a sibling AddOn/runtime dependency. Other cross-product mentions are history.
UNRESOLVED_SHARED_FILES: none.

CI: no .github workflows existed. TEF build checks the TEF TOC/Lua tests and
local TEK suite; Retail packaging scripts are absent. Package outputs use TEF
names. Build/startup success does not substitute for live input acceptance.

No remote push was performed.

## TEF validation at independent start

PASS: 327 Lua5.1 cases; 235 pytest cases with 17 subtests; 229 TEK unittest
cases; 2 acceptance harness mock cases; 37 Lua syntax files; standalone
baseline and compileall. Relocation test copied source to a temporary isolated
project, removed PYTHONPATH, and passed both baseline and Lua/TEK interop.
PASS: isolated TEK-TEF.exe build and AddOn source package.
NOT_RUN: executable startup smoke and real Windows/game input (deliberately
not launched, to preserve the active host and existing user state).
No .git object alternates; TEK source files are distinct physical copies.
