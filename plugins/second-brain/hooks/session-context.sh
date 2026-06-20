#!/usr/bin/env bash
# SessionStart context hook — inject the vault conventions when the session is
# working INSIDE the configured second-brain vault. Fires on every session
# globally; silent no-op otherwise. NO LLM, no network, no git. Fast.
# Design: see this plugin's README.md.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0   # need jq to emit/read JSON safely

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- locate the target vault (same precedence as session-capture.sh) ---
vault_arg="${1:-${SECOND_BRAIN_VAULT:-}}"
[ -n "$vault_arg" ] || exit 0
VAULT_ROOT="$(cd "$vault_arg" 2>/dev/null && pwd)"
[ -n "${VAULT_ROOT:-}" ] || exit 0

# --- determine the session's working dir: payload .cwd, else $CLAUDE_PROJECT_DIR ---
payload="$(cat)"
cwd="$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-}"
[ -n "$cwd" ] || exit 0
cwd_real="$(cd "$cwd" 2>/dev/null && pwd || printf '%s' "$cwd")"

# --- in-vault gate: only inject when working inside the vault ---
case "$cwd_real" in
  "$VAULT_ROOT"|"$VAULT_ROOT"/*) ;;   # inside the vault → proceed
  *) exit 0 ;;                          # elsewhere → nothing (recall is handled by ~/.claude/CLAUDE.md)
esac

# --- load the plugin-owned conventions (env override for tests) ---
CONV="${SECOND_BRAIN_CONVENTIONS:-$SCRIPT_DIR/../assets/vault-conventions.md}"
[ -r "$CONV" ] || exit 0
conv="$(cat "$CONV")"
[ -n "$conv" ] || exit 0

# --- emit additionalContext (jq escapes the text) ---
jq -n --arg ctx "$conv" \
  '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}'
exit 0
