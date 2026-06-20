#!/usr/bin/env bash
# Job A — mechanical session capture for the second-brain vault.
# Triggered by a global Claude Code SessionEnd hook. Reads the hook payload on
# stdin, copies the session transcript into raw/, and (re)writes an inbox/ pointer.
# NO LLM, no summarising, no journal, no wiki, no git. Fast and deterministic.
# Design: see this plugin's README.md.
set -uo pipefail

command -v jq    >/dev/null 2>&1 || exit 0   # degrade to no-op if jq is unavailable
command -v shasum >/dev/null 2>&1 || exit 0   # degrade to no-op if shasum is unavailable

# --- locate the target vault ---
# Precedence: $1 (vault_path from the plugin hook) → $SECOND_BRAIN_VAULT (power users / tests).
# This hook fires on EVERY session globally; if the vault is unconfigured or missing,
# no-op silently — never error on an unrelated session.
vault_arg="${1:-${SECOND_BRAIN_VAULT:-}}"
[ -n "$vault_arg" ] || exit 0
VAULT_ROOT="$(cd "$vault_arg" 2>/dev/null && pwd)"
[ -n "${VAULT_ROOT:-}" ] || exit 0

# --- read & parse the hook payload ---
payload="$(cat)"
sid="$(printf '%s' "$payload"        | jq -r '.session_id // empty')"
transcript="$(printf '%s' "$payload" | jq -r '.transcript_path // empty')"
cwd="$(printf '%s' "$payload"        | jq -r '.cwd // empty')"
hook="$(printf '%s' "$payload"       | jq -r '.hook_event_name // "SessionEnd"')"
# reason lives in the .hook.json payload but never gates capture.

# --- guards ---
[ -n "$sid" ] || exit 0
case "$sid"  in *[!A-Za-z0-9_-]*) exit 0 ;; esac   # reject path-traversal in session_id
case "$hook" in ""|*[!A-Za-z0-9_-]*) exit 0 ;; esac # reject path-traversal in hook_event_name
if [ -n "$cwd" ]; then
  cwd_real="$(cd "$cwd" 2>/dev/null && pwd || printf '%s' "$cwd")"
  case "$cwd_real" in
    "$VAULT_ROOT"|"$VAULT_ROOT"/*) exit 0 ;;   # self-capture: the brain managing itself
  esac
fi
[ -r "$transcript" ] || exit 0

# --- derive the raw-home anchor (session start) ---
# Earliest non-null .timestamp (ISO-8601 UTC sorts lexically = chronologically).
# NOT head -1: the first line is usually a null-timestamp metadata record.
start_ts="$(jq -rc 'select(.timestamp != null) | .timestamp' "$transcript" 2>/dev/null | sort | head -1)"
[ -n "$start_ts" ] || start_ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"   # fallback: capture-time
start_date="${start_ts:0:10}"   # YYYY-MM-DD
month="${start_ts:0:7}"         # YYYY-MM

project="$(basename "$cwd")"
case "$project" in ""|".") project="unknown";; esac
hash="$(shasum -a 256 "$transcript" | cut -d' ' -f1 | cut -c1-8)"

# --- anchor all versions of a sid to ONE dir + identity ---
# A later version can compute a different start-month (capture-time fallback vs a real
# earliest timestamp), which would split a sid's versions, metadata, and pointer across
# month dirs. Reuse any dir already holding this sid, and adopt the canonical start_date/
# project from its write-once metadata, so every version of a sid stays unified.
existing="$(ls "$VAULT_ROOT/raw/$hook/"*/"$sid".metadata.json 2>/dev/null | head -1)"
[ -n "$existing" ] || existing="$(ls "$VAULT_ROOT/raw/$hook/"*/"$sid".*.jsonl 2>/dev/null | head -1)"
if [ -n "$existing" ]; then
  raw_dir="$(cd "$(dirname "$existing")" && pwd)"
  month="$(basename "$raw_dir")"
  prior_meta="$raw_dir/$sid.metadata.json"
  if [ -f "$prior_meta" ]; then
    sd="$(jq -r '.start_date // empty' "$prior_meta" 2>/dev/null)"; [ -n "$sd" ] && start_date="$sd"
    pj="$(jq -r '.project // empty' "$prior_meta" 2>/dev/null)"; [ -n "$pj" ] && project="$pj"
  fi
else
  raw_dir="$VAULT_ROOT/raw/$hook/$month"
fi
mkdir -p "$raw_dir"
target="$raw_dir/$sid.$hash.jsonl"
hookjson="$raw_dir/$sid.$hash.hook.json"
metadata="$raw_dir/$sid.metadata.json"

# --- capture the version (collect-all: skip if this exact version exists) ---
[ -f "$target" ] && exit 0
cp "$transcript" "$target" || exit 0   # capture failed → do NOT enqueue an orphan pointer
printf '%s' "$payload" | jq '.' > "$hookjson" 2>/dev/null || printf '%s\n' "$payload" > "$hookjson"

# --- metadata (write-once) ---
if [ ! -f "$metadata" ]; then
  jq -n --arg sid "$sid" --arg project "$project" --arg start_date "$start_date" \
    '{session_id:$sid, project:$project, start_date:$start_date}' > "$metadata"
fi

# --- enqueue one pointer per session ---
mkdir -p "$VAULT_ROOT/inbox"
pointer="$VAULT_ROOT/inbox/$start_date-$project-$sid.md"
cat > "$pointer" <<EOF
---
session_id: $sid
project: $project
start_date: $start_date
raw_dir: raw/$hook/$month
---
EOF

exit 0
