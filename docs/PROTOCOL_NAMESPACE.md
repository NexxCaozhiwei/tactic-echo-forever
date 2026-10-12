# Protocol namespace TEF

Project: TEF. Local host: TEF-TEK. Version is independently managed by this
project's VERSION, currently 1.0.1. Trace and build metadata identify TEF.
TEAP v3 wire bytes and CRC remain unchanged at the split. No project selector
exists on this wire, so TE/TEF frames cannot be distinguished by namespace.
Enable only one AddOn signal source at a time. Future divergent wire fields
require an explicit protocol version/namespace migration. Independent copies
of the existing compatibility catalog are retained because the ActionCode=0
binding-token path uses the existing v3 catalog envelope. The catalog is not
an Infinite ability model and does not authorize guessed ranks.
