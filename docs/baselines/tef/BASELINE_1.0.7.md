# TEF 1.0.7

Manual skip-unavailable accepts publicly enabled, inactive cooldown as no cooldown omission reason before requiring public numeric timing or isOnGCD. It does not infer general readiness, skip UNKNOWN, or bypass usability, target, range, cast, receipt or input gates. Active cooldown/GCD discrimination is otherwise unchanged; its event-timing limitations are outside this targeted inactive-path fix.

Lua 5.1 regression covers Secret timing and absent isOnGCD with repeated exact success, unknown enabled/usability, and active/unknown cooldown blocking. Offline tests and deployment hashes do not prove in-game dispatch.
