# 1.0.2 cast-tail queue trial

Enable the experimental toggle on Settings → TEK, then close settings and restart dispatch. It is off by default. Only fixed-sequence ordinary player casting is eligible, with a next step or remaining repeat; no APL or loop-boundary prediction. Current channeling/UNKNOWN and Shoot remain blocking. The observed missile sample 5143 is excluded as a destination.

The existing 50ms heartbeat checks public start/end times, current spell and initiation identity. No static cast-time estimate or GCD/61304 read is used. The maximum lead is min(0.20 seconds, public SpellQueueWindow). A smaller or unknown window reduces or prevents the offer. Physical input timing also depends on TEK sampling and safety gates; exactly 2.300 seconds is not promised.

The next request uses the same Dispatch/TEAP v3/TEK chain. A future SENT/START is associated with its distinct GUID, future index and receipt serial; it cannot count before A's exact success. A successful A promotes the reservation, including same-ID repeats. Failure/early success before A retires the queued identity; a second speculative logical request is not opened during the same A initiation. Existing TEK transport can still re-offer pending input under its unchanged replay/rate gates until a client receipt arrives.

Trial: use two independently learned exact direct spell bindings in a short fixed sequence. Watch A's 2.5-second cast: the next offer may begin in the last 0.2 seconds. Confirm B only starts after A, counts change on exact successes, interruption does not skip A, and stopping does not resume. Repeat with adjacent same-ID casts. Do not modify macros, skill bindings, WTF or SpellQueueWindow as part of this trial.

Offline tests cover normal and adjacent-repeat promotion, rejected/out-of-order receipts, failure before SENT, A interruption, stop/reset, public timing and smaller window, Secret/UNKNOWN, binding/focus/setting revalidation, completion/Shoot/channel/APL exclusions. Real client queue acceptance, Hook, SendInput and game effects remain unverified.
