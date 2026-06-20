#!/usr/bin/env bash
# Zero-dependency test harness for session-context.sh (bash 3.2 compatible).
# Run all:   bash plugins/second-brain/tests/test-session-context.sh
# Run one:   bash plugins/second-brain/tests/test-session-context.sh test_inject_when_in_vault
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../hooks/session-context.sh"

pass=0; fail=0
_fail() { printf 'FAIL: %s\n' "$1" >&2; fail=$((fail+1)); }
_ok()   { pass=$((pass+1)); }
assert_eq()      { if [ "$1" = "$2" ]; then _ok; else _fail "${3:-expected [$2] got [$1]}"; fi; }

new_dir() { local d; d="$(mktemp -d)"; (cd "$d" && pwd); }

SENTINEL="SENTINEL_CONVENTIONS_$$"
CONV_FIXTURE="$(new_dir)/conventions.md"
printf '# conv\n%s\n' "$SENTINEL" > "$CONV_FIXTURE"

# Run the SessionStart hook. args: vault cwd [conventions_file]
run_ctx() {
  local conv="${3:-$CONV_FIXTURE}"
  jq -nc --arg cwd "$2" '{cwd:$cwd, hook_event_name:"SessionStart", source:"startup"}' \
  | SECOND_BRAIN_VAULT="$1" SECOND_BRAIN_CONVENTIONS="$conv" bash "$HOOK"
}

test_inject_when_in_vault() {
  local vault out
  vault="$(new_dir)"
  out="$(run_ctx "$vault" "$vault")"
  assert_eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')" "SessionStart" "emits SessionStart output"
  assert_eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -c "$SENTINEL")" "1" "injects the conventions text"
}

test_inject_when_inside_subdir() {
  local vault sub out
  vault="$(new_dir)"; sub="$vault/projects/x"; mkdir -p "$sub"
  out="$(run_ctx "$vault" "$sub")"
  assert_eq "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' | grep -c "$SENTINEL")" "1" "injects when cwd is inside the vault"
}

test_noop_when_cwd_outside_vault() {
  local vault other out rc
  vault="$(new_dir)"; other="$(new_dir)"
  out="$(run_ctx "$vault" "$other")"; rc=$?
  assert_eq "$rc" "0" "outside-vault exits 0"
  assert_eq "$out" ""  "outside-vault injects nothing"
}

test_noop_when_vault_unset() {
  local out rc cwd
  cwd="$(new_dir)"
  out="$(jq -nc --arg cwd "$cwd" '{cwd:$cwd, hook_event_name:"SessionStart", source:"startup"}' \
    | env -u SECOND_BRAIN_VAULT SECOND_BRAIN_CONVENTIONS="$CONV_FIXTURE" bash "$HOOK")"; rc=$?
  assert_eq "$rc" "0" "unconfigured exits 0"
  assert_eq "$out" ""  "unconfigured injects nothing"
}

test_noop_when_conventions_missing() {
  local vault out rc
  vault="$(new_dir)"
  out="$(run_ctx "$vault" "$vault" "/no/such/conventions.md")"; rc=$?
  assert_eq "$rc" "0" "missing conventions exits 0"
  assert_eq "$out" ""  "missing conventions injects nothing"
}

# --- runner (bash 3.2: no mapfile/arrays) ---
if [ "$#" -eq 0 ]; then set -- $(declare -F | awk '{print $3}' | grep '^test_' | sort); fi
for _t in "$@"; do "$_t"; done
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
