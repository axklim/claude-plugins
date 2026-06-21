---
name: sync
description: Refresh the second-brain conventions and recall copies from the plugin after an update. Run after /plugin update so the vault's imported conventions and the ~/.claude recall file match the installed plugin version.
---

# Sync second-brain conventions + recall

The vault imports a COPY of the plugin's conventions, and recall lives in a copy under
`~/.claude/`. After `/plugin update`, refresh those copies from the plugin's canonical assets so
the imports reflect the installed version.

## Steps

1. **Resolve the vault path** from `$CLAUDE_PLUGIN_OPTION_VAULT_PATH` (or ask). Expand `~`. If it
   does not resolve to a directory, STOP and tell the user to set `vault_path` or run
   `/second-brain:init-vault`.

2. **Refresh conventions:**
   ```bash
   mkdir -p "$VAULT/.second-brain"
   cp "$CLAUDE_PLUGIN_ROOT/assets/vault-conventions.md" "$VAULT/.second-brain/conventions.md"
   ```
   Report whether it changed (compare `shasum -a 256` of the file before vs after, or note "no
   change").

3. **Refresh recall:** render `$CLAUDE_PLUGIN_ROOT/assets/recall-instruction.md`, replacing every
   `<VAULT_PATH>` with the resolved vault path, and write it to `~/.claude/second-brain/recall.md`
   (`mkdir -p ~/.claude/second-brain` first). If `~/.claude/CLAUDE.md` does not contain
   `@~/.claude/second-brain/recall.md`, tell the user to run `/second-brain:init-vault` (or offer to
   add the single import line, only on explicit confirmation).

4. **Report:** what was refreshed and whether anything changed. Note that the vault's
   `.second-brain/conventions.md` is tracked in the vault's git — the user can commit the update.
