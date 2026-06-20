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

6. **Point capture at the vault.** Tell the user to set the plugin's `vault_path` config to this
   directory (via `/plugin` config) if it isn't already, so the `SessionEnd` hook captures here.
   Sessions run *inside* the vault are intentionally skipped (self-capture guard), so they should
   work in their other projects to generate captures.

7. **Report:** the created path, the files scaffolded, and the next steps (set `vault_path`, then
   run `/second-brain:file-inbox` after some sessions accumulate).
