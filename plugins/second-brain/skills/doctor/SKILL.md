---
name: doctor
description: Health-check the second-brain setup — verify vault_path resolves, the vault looks valid, captures are landing, the imported conventions are current, and recall is wired. Run if sessions aren't showing up or after a plugin update.
---

# Diagnose second-brain

Confirm capture is live, the imported conventions are current, and recall is wired. The capture
hook is a deliberate silent no-op when misconfigured, so this skill is the positive confirmation
it cannot give. Run each check, report PASS / FAIL / WARN with the actual value, then a one-line
overall verdict and the single next action for anything not green. Read-only — make no changes.

1. **vault_path set?** Read `$CLAUDE_PLUGIN_OPTION_VAULT_PATH`.
   - empty/unset → **FAIL**: "vault_path is not configured — set it via `/plugin` config, or run
     `/second-brain:init-vault <path>`." Nothing below can pass; stop.

2. **Resolves to a directory?** `cd "$vault_path" 2>/dev/null && pwd`.
   - fails → **FAIL**: the configured path does not exist or is not a directory. Show the raw value.

3. **Writable?** `[ -w "<resolved>" ]`.
   - not writable → **FAIL**: captures cannot be written there.

4. **Looks like a vault?** Check the resolved dir has `raw/`, `inbox/`, `CLAUDE.md`, and
   `.second-brain/conventions.md`.
   - missing any → **WARN**: "doesn't look like a fully-initialized second-brain vault — run
     `/second-brain:init-vault` against this path."

5. **Captures landing?** Most recent transcript: `ls -t "<resolved>"/raw/*/*/*.jsonl 2>/dev/null | head -1`.
   - none → **WARN**: "no captures yet — run a session in another project, then re-check (sessions
     inside the vault are skipped by design)."
   - found → **PASS**: show the newest capture's path + mtime.

6. **Pending queue (informational).** Count `inbox/*.md` (excluding `.keep`) awaiting `/second-brain:file-inbox`.

7. **Conventions current?** Compare the vault's imported copy against the plugin's canonical asset:
   `shasum -a 256 "<resolved>/.second-brain/conventions.md"` vs
   `shasum -a 256 "$CLAUDE_PLUGIN_ROOT/assets/vault-conventions.md"` (compare the hashes only).
   - match → **PASS**: imported conventions are current.
   - differ → **WARN**: "conventions are stale (plugin updated since last sync) — run
     `/second-brain:sync`."
   - vault copy missing → **WARN**: "no imported conventions — run `/second-brain:init-vault` or
     `/second-brain:sync`."

8. **Recall wired?** Check `~/.claude/CLAUDE.md` imports the recall file:
   `grep -q '@~/.claude/second-brain/recall.md' ~/.claude/CLAUDE.md 2>/dev/null` AND
   `test -f ~/.claude/second-brain/recall.md`.
   - both → **PASS**: cross-session recall is wired.
   - import line missing → **WARN**: "recall is not wired into `~/.claude/CLAUDE.md` — Claude won't
     consult the vault from other projects. Run `/second-brain:init-vault` (it offers to add the
     `@~/.claude/second-brain/recall.md` import)."
   - recall file missing → **WARN**: "the recall file is missing — run `/second-brain:sync`."

End with **Overall: capture is LIVE / NOT live**, **conventions CURRENT / STALE**, and **recall
WIRED / NOT wired**, followed by the one fix to apply for each that is not green.
