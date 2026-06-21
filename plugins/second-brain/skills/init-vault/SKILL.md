---
name: init-vault
description: Scaffold a fresh second-brain vault from the plugin's bundled template, copy in the current conventions, and wire cross-session recall. Run once when setting up a new vault, optionally passing the target directory.
---

# Initialize a second-brain vault

Scaffold a new vault, import the plugin's conventions into it, and wire recall.

## Steps

1. **Resolve the target path.** Use, in order: the path the user passed as an argument; else the
   configured `vault_path` (env `$CLAUDE_PLUGIN_OPTION_VAULT_PATH`, if set); else ask the user.
   Expand `~` to `$HOME`.

2. **Safety check.** If the target exists and is a non-empty directory, STOP and tell the user —
   never overwrite existing content. A fresh directory is fine.

3. **Copy the skeleton** (small `CLAUDE.md` that imports the conventions, folder layout, `.obsidian/`
   config), including dotfiles:
   ```bash
   mkdir -p "$TARGET"
   cp -R "$CLAUDE_PLUGIN_ROOT/assets/vault-template/." "$TARGET/"
   ```

4. **Copy in the current conventions.** The single source of truth lives in the plugin; the vault
   gets a copy its `CLAUDE.md` imports:
   ```bash
   mkdir -p "$TARGET/.second-brain"
   cp "$CLAUDE_PLUGIN_ROOT/assets/vault-conventions.md" "$TARGET/.second-brain/conventions.md"
   ```

5. **Initialize git:**
   ```bash
   git -C "$TARGET" init -q
   git -C "$TARGET" add -A
   git -C "$TARGET" commit -qm "chore: initialize second-brain vault from template"
   ```

6. **Point capture at the vault, and confirm it.** Read `$CLAUDE_PLUGIN_OPTION_VAULT_PATH`:
   - If it already resolves to this vault, echo: "Capture target: `<resolved path>` — sessions will
     be captured here."
   - If unset or elsewhere, tell the user to set it (via `/plugin` config) and warn that until then
     no sessions are captured (the capture hook is a silent no-op when unset). Sessions run *inside*
     the vault are skipped (self-capture guard), so work in other projects to generate captures.

7. **Wire cross-session recall (offer).** So Claude can consult the brain from *other* projects:
   - Render `$CLAUDE_PLUGIN_ROOT/assets/recall-instruction.md`, replacing every `<VAULT_PATH>` with
     the resolved vault path, and write it to `~/.claude/second-brain/recall.md`
     (`mkdir -p ~/.claude/second-brain` first).
   - Ensure `~/.claude/CLAUDE.md` imports it: if it does NOT already contain the line
     `@~/.claude/second-brain/recall.md`, **offer to append that one line** (create the file if
     absent). Append ONLY on explicit user confirmation; otherwise print the line for the user to
     add. Never touch anything else in that file.
   - Note: the first time, Claude Code shows a one-time approval dialog for this external import.
   Explain: without this, recall works only while you are inside the vault.

8. **Report:** the created path, files scaffolded, the resolved capture target (or the unset
   warning), whether recall is now wired, and next steps — run `/second-brain:doctor` to confirm,
   and `/second-brain:sync` after a `/plugin update` to refresh the imported conventions + recall.
