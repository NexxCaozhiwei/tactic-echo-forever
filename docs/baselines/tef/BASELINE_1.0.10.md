# TEF 1.0.10

User-configurable cast-tail queue lead: 0–0.50 seconds, UI step 0.05, default 0.20 for existing configurations. Zero disables look-ahead. Window remains bounded by public client SpellQueueWindow, fixed ordinary casts only. Setter stops dispatch; unknown timing remains blocked. Existing receipt and queue teardown behavior is unchanged. Lua regression checks zero, 0.50, client cap, Secret migration and setter invalidation. In-game queue stability is still unverified.
