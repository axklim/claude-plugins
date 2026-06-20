---
name: doctor
description: Health-check the second-brain capture pipeline — verify vault_path is set and resolvable, the vault looks valid, and captures are actually landing. Run if sessions are not showing up.
---

# Diagnose second-brain capture

Confirm that session capture is live and pointed at the right vault. The capture hook is a
deliberate silent no-op when misconfigured (it fires on every session, so it must never error) —
which means a typo'd or unset `vault_path` loses sessions with no signal. This skill is the
positive confirmation the hook itself cannot give.

Run each check, report it as PASS / FAIL / WARN with the actual value, then a one-line overall
verdict and the single next action for any failure. Read-only — make no changes.

1. **vault_path set?** Read `$CLAUDE_PLUGIN_OPTION_VAULT_PATH`.
   - empty/unset → **FAIL**: "vault_path is not configured — set second-brain's `vault_path` via
     `/plugin` config, or run `/second-brain:init-vault <path>`." Nothing below can pass; stop.

2. **Resolves to a directory?** `cd "$vault_path" 2>/dev/null && pwd`.
   - fails → **FAIL**: the configured path does not exist or is not a directory. Show the raw value.

3. **Writable?** `[ -w "<resolved>" ]`.
   - not writable → **FAIL**: captures cannot be written there.

4. **Looks like a vault?** Check the resolved dir has `raw/`, `inbox/`, and `CLAUDE.md`.
   - missing any → **WARN**: "doesn't look like a second-brain vault — did you run
     `/second-brain:init-vault` against this path?"

5. **Captures landing?** Find the most recent transcript:
   `ls -t "<resolved>"/raw/*/*/*.jsonl 2>/dev/null | head -1` (newest captured session).
   - none → **WARN**: "no captures yet — run a session in another project, then re-check.
     Sessions run *inside* the vault are skipped by design (self-capture guard)."
   - found → **PASS**: show the newest capture's path and modification time as proof capture works.

6. **Pending queue (informational).** Count `inbox/*.md` (excluding `.keep`) — how many captured
   sessions are waiting for `/second-brain:file-inbox`.

End with **Overall: capture is LIVE** (vault_path resolves, writable, recent capture present) or
**Overall: capture is NOT live**, followed by the one fix to apply.
