# TEF 1.0.2

Experimental opt-in fixed-sequence ordinary cast-tail queue. The lead is public min(0.20 seconds, client SpellQueueWindow), with no GCD/61304 query or cooldown readiness inference. UNKNOWN blocks early dispatch. Settings default off; changing the setting stops intent.

One bounded next-attempt reservation supports distinct next IDs and same-ID repeats. Current exact SUCCEEDED alone advances counts and promotes the queued initiation's future receipt. Failed/retired GUIDs cannot count. Manual stop, edit/reset/world and fault invalidate queued identities. Existing Dispatch/TEAP v3/TEF TEK input and safety gates remain; no new timers, hooks or input paths.

No APL, channels, 5019 Shoot or loop-boundary look-ahead. Ordinary casting presence remains blocking outside the explicitly enabled public tail window. No live queue, SendInput or game success claim; user acceptance remains pending.

Offline validation: 206 fixed/runtime Lua cases + 131 APL Lua cases; 235 pytest cases / 17 subtests; 229 TEK unittest cases; 2 mocked acceptance cases; 38 Lua 5.1 syntax files; baseline and compileall passed. Real input and client queue acceptance remain pending.
