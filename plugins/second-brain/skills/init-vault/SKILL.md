---
name: init-vault
description: Scaffold a fresh second-brain vault from the plugin's bundled template and git-init it. Run once when setting up a new vault, optionally passing the target directory.
---

# Initialize a second-brain vault

Scaffold a new, empty vault from the plugin's bundled template.

## Steps

1. **Resolve the target path.** Use, in order: the path the user passed as an argument; else the
   plugin's configured `vault_path` (env `$CLAUDE_PLUGIN_OPTION_VAULT_PATH`, if set); else ask the
   user where to create the vault. Expand `~` to `$HOME`.

2. **Safety check.** If the target exists and is a non-empty directory, STOP and tell the user —
   never overwrite existing content. Creating the directory fresh is fine.

3. **Locate the template.** It ships with this plugin at `$CLAUDE_PLUGIN_ROOT/assets/vault-template`
   (the `CLAUDE_PLUGIN_ROOT` env var is set whenever this plugin is active).

4. **Copy the skeleton** into the target, including dotfiles:

   ```bash
   mkdir -p "$TARGET"
   cp -R "$CLAUDE_PLUGIN_ROOT/assets/vault-template/." "$TARGET/"
   ```

5. **Initialize git** so the vault is versioned from the start:

   ```bash
   git -C "$TARGET" init -q
   git -C "$TARGET" add -A
   git -C "$TARGET" commit -qm "chore: initialize second-brain vault from template"
   ```

6. **Point capture at the vault, and confirm it.** Capture only works once the plugin's
   `vault_path` config points here. Read `$CLAUDE_PLUGIN_OPTION_VAULT_PATH`:
   - If it already resolves to this vault, echo to the user: "Capture target: `<resolved path>`
     — sessions will be captured here."
   - If it is unset or points elsewhere, tell the user to set it to this directory (via `/plugin`
     config) and warn that **until then no sessions are captured** — the hook is a silent no-op
     when `vault_path` is unset or unresolvable.
   Sessions run *inside* the vault are intentionally skipped (self-capture guard), so the user
   should work in their other projects to generate captures.

7. **Report:** the created path, the files scaffolded, the resolved capture target (or the
   warning that `vault_path` is not yet set), and the next steps — run `/second-brain:doctor` to
   confirm capture is live, then `/second-brain:file-inbox` after some sessions accumulate.
