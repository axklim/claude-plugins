#!/usr/bin/env bash
# Zero-dependency test harness for session-capture.sh (bash 3.2 compatible).
# Run all:   bash plugins/second-brain/tests/test-session-capture.sh
# Run one:   bash plugins/second-brain/tests/test-session-capture.sh test_happy_path
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HERE/../hooks/session-capture.sh"

pass=0; fail=0
_fail() { printf 'FAIL: %s\n' "$1" >&2; fail=$((fail+1)); }
_ok()   { pass=$((pass+1)); }
assert_file()    { if [ -f "$1" ]; then _ok; else _fail "${2:-expected file: $1}"; fi; }
assert_no_path() { if [ ! -e "$1" ]; then _ok; else _fail "${2:-unexpected path: $1}"; fi; }
assert_eq()      { if [ "$1" = "$2" ]; then _ok; else _fail "${3:-expected [$2] got [$1]}"; fi; }
assert_in_file() { if grep -qF "$2" "$1" 2>/dev/null; then _ok; else _fail "${3:-[$1] missing [$2]}"; fi; }

new_dir() { local d; d="$(mktemp -d)"; (cd "$d" && pwd); }   # canonical temp dir
short_hash() { shasum -a 256 "$1" | cut -d' ' -f1 | cut -c1-8; }

# Run the hook against $vault with a SessionEnd payload.
# args: vault sid transcript_path cwd [reason]
run_hook() {
  jq -nc --arg sid "$2" --arg t "$3" --arg cwd "$4" --arg r "${5:-other}" \
    '{session_id:$sid, transcript_path:$t, cwd:$cwd, hook_event_name:"SessionEnd", reason:$r}' \
  | SECOND_BRAIN_VAULT="$1" bash "$HOOK"
}

# Realistic transcript: first line is a NULL-timestamp metadata record; the
# earliest real timestamp is 2026-06-30 and a later one is 2026-07-01 — so the
# raw-home month must be 2026-06 (the MIN), proving we use neither head -1 nor max.
fixture_realistic() {
  {
    printf '%s\n' '{"type":"last-prompt","sessionId":"x"}'
    printf '%s\n' '{"type":"user","timestamp":"2026-06-30T23:50:00.000Z","message":"hi"}'
    printf '%s\n' '{"type":"assistant","timestamp":"2026-07-01T00:10:00.000Z","message":"yo"}'
  } > "$1"
}

test_happy_path() {
  local vault sid t cwd proj rawdir h
  vault="$(new_dir)"; sid="11111111-1111-1111-1111-111111111111"
  t="$vault/transcript.jsonl"; fixture_realistic "$t"
  cwd="$(new_dir)"; proj="$(basename "$cwd")"
  run_hook "$vault" "$sid" "$t" "$cwd"
  rawdir="$vault/raw/SessionEnd/2026-06"; h="$(short_hash "$t")"
  assert_file "$rawdir/$sid.$h.jsonl"      "transcript copied into raw/ under the START month"
  assert_file "$rawdir/$sid.$h.hook.json"  "hook payload written"
  assert_file "$rawdir/$sid.metadata.json" "metadata written"
  assert_eq "$(jq -r .session_id "$rawdir/$sid.metadata.json")" "$sid"        "metadata.session_id"
  assert_eq "$(jq -r .start_date "$rawdir/$sid.metadata.json")" "2026-06-30"  "metadata.start_date = earliest day"
  assert_eq "$(jq -r .session_id "$rawdir/$sid.$h.hook.json")"  "$sid"        "hook.json carries the payload"
  assert_file "$vault/inbox/2026-06-30-$proj-$sid.md" "inbox pointer written"
  assert_in_file "$vault/inbox/2026-06-30-$proj-$sid.md" "raw_dir: raw/SessionEnd/2026-06" "pointer raw_dir"
}

# Degenerate 2-line stub: no timestamps anywhere (these really exist).
fixture_stub() {
  {
    printf '%s\n' '{"type":"agent-name"}'
    printf '%s\n' '{"type":"ai-title"}'
  } > "$1"
}

test_fallback_capture_time() {
  local vault sid t cwd h month
  vault="$(new_dir)"; sid="22222222-2222-2222-2222-222222222222"
  t="$vault/stub.jsonl"; fixture_stub "$t"
  cwd="$(new_dir)"
  run_hook "$vault" "$sid" "$t" "$cwd"
  month="$(date -u +%Y-%m)"; h="$(short_hash "$t")"
  assert_file "$vault/raw/SessionEnd/$month/$sid.$h.jsonl" "stub captured under capture-time month"
  assert_eq "$(jq -r .start_date "$vault/raw/SessionEnd/$month/$sid.metadata.json")" \
            "$(date -u +%Y-%m-%d)" "stub start_date = capture-time date"
}

test_self_capture_guard() {
  local vault sid t
  vault="$(new_dir)"; sid="33333333-3333-3333-3333-333333333333"
  t="$vault/transcript.jsonl"; fixture_realistic "$t"
  run_hook "$vault" "$sid" "$t" "$vault"           # cwd IS the vault root
  assert_no_path "$vault/raw"   "cwd==vault → no raw/ created"
  mkdir -p "$vault/sub"
  run_hook "$vault" "$sid" "$t" "$vault/sub"        # cwd is INSIDE the vault
  assert_no_path "$vault/raw"   "cwd inside vault → no raw/ created"
}

test_unreadable_transcript() {
  local vault sid cwd
  vault="$(new_dir)"; sid="44444444-4444-4444-4444-444444444444"; cwd="$(new_dir)"
  run_hook "$vault" "$sid" "$cwd/nope.jsonl" "$cwd"
  assert_no_path "$vault/raw"   "missing transcript → no capture"
}

test_collect_all() {
  local vault sid t cwd rawdir h1 h2 ptr ptr_before
  vault="$(new_dir)"; sid="55555555-5555-5555-5555-555555555555"
  t="$vault/t.jsonl"; fixture_realistic "$t"; cwd="$(new_dir)"
  rawdir="$vault/raw/SessionEnd/2026-06"

  run_hook "$vault" "$sid" "$t" "$cwd"
  h1="$(short_hash "$t")"
  ptr="$vault/inbox/2026-06-30-$(basename "$cwd")-$sid.md"

  # Seed sentinels to prove the guards skip the re-write paths.
  printf 'SENTINEL_POINTER\n' >> "$ptr"
  jq '. + {_sentinel:"keep"}' "$rawdir/$sid.metadata.json" > "$rawdir/m.tmp" && mv "$rawdir/m.tmp" "$rawdir/$sid.metadata.json"

  # (a) identical re-run → exit before enqueue → pointer must be byte-identical.
  #     The seeded sentinel makes current content differ from a fresh enqueue, so any
  #     re-write (clobber OR append) changes the bytes; a true no-op leaves them unchanged.
  ptr_before="$(cat "$ptr")"
  run_hook "$vault" "$sid" "$t" "$cwd"
  assert_eq "$(cat "$ptr")" "$ptr_before" "identical re-run leaves the pointer byte-identical (no re-enqueue)"

  # (b) changed transcript → new hash pair; original retained; metadata write-once.
  printf '%s\n' '{"type":"user","timestamp":"2026-06-30T23:55:00.000Z","message":"more"}' >> "$t"
  run_hook "$vault" "$sid" "$t" "$cwd"
  h2="$(short_hash "$t")"
  assert_file "$rawdir/$sid.$h2.jsonl" "changed transcript → new version captured"
  assert_file "$rawdir/$sid.$h1.jsonl" "original version retained"
  assert_eq "$(jq -r ._sentinel "$rawdir/$sid.metadata.json")" "keep" "metadata is write-once"
}

test_rejects_unsafe_path_components() {
  local vault t cwd
  vault="$(new_dir)"; t="$vault/t.jsonl"; fixture_realistic "$t"; cwd="$(new_dir)"
  # traversal in session_id → rejected, nothing written
  run_hook "$vault" "../../evil" "$t" "$cwd"
  assert_no_path "$vault/raw" "traversal session_id rejected (no raw/ created)"
  # traversal in hook_event_name (inline payload, since run_hook hardcodes it) → rejected
  jq -nc --arg sid "77777777-7777-7777-7777-777777777777" --arg t "$t" --arg cwd "$cwd" \
    '{session_id:$sid, transcript_path:$t, cwd:$cwd, hook_event_name:"../../../tmp/PWNED", reason:"other"}' \
  | SECOND_BRAIN_VAULT="$vault" bash "$HOOK"
  assert_no_path "$vault/raw" "traversal hook_event_name rejected (no raw/ created)"
}

test_no_orphan_pointer_on_capture_failure() {
  [ "$(id -u)" = "0" ] && return   # root bypasses file perms; skip this test as root
  local vault sid t cwd
  vault="$(new_dir)"; sid="66666666-6666-6666-6666-666666666666"
  t="$vault/t.jsonl"; fixture_realistic "$t"; cwd="$(new_dir)"
  mkdir -p "$vault/raw"; chmod 500 "$vault/raw"     # read-only → raw subdir mkdir + cp fail
  run_hook "$vault" "$sid" "$t" "$cwd"
  chmod 700 "$vault/raw"                            # restore for assertions/cleanup
  assert_no_path "$vault/inbox/2026-06-30-$(basename "$cwd")-$sid.md" "no inbox pointer when capture write fails"
}

# --- plugin-mode behaviours: vault via positional $1, and no-op when unconfigured ---

test_vault_via_positional_arg() {
  local vault sid t cwd proj h
  vault="$(new_dir)"; sid="88888888-8888-8888-8888-888888888888"
  t="$vault/transcript.jsonl"; fixture_realistic "$t"
  cwd="$(new_dir)"; proj="$(basename "$cwd")"
  # No SECOND_BRAIN_VAULT in the env — vault must come from $1 only.
  jq -nc --arg sid "$sid" --arg t "$t" --arg cwd "$cwd" \
    '{session_id:$sid, transcript_path:$t, cwd:$cwd, hook_event_name:"SessionEnd", reason:"other"}' \
  | env -u SECOND_BRAIN_VAULT bash "$HOOK" "$vault"
  h="$(short_hash "$t")"
  # the 2026-06 / 2026-06-30 dates below derive from fixture_realistic's earliest timestamp
  assert_file "$vault/raw/SessionEnd/2026-06/$sid.$h.jsonl" "vault resolved from positional arg \$1"
  assert_file "$vault/inbox/2026-06-30-$proj-$sid.md"       "pointer written when vault via \$1"
}

test_noop_when_vault_unset() {
  local sid t cwd out rc
  sid="99999999-9999-9999-9999-999999999999"
  t="$(new_dir)/t.jsonl"; fixture_realistic "$t"; cwd="$(new_dir)"
  # Neither $1 nor $SECOND_BRAIN_VAULT → must exit 0 and write nothing.
  out="$(jq -nc --arg sid "$sid" --arg t "$t" --arg cwd "$cwd" \
    '{session_id:$sid, transcript_path:$t, cwd:$cwd, hook_event_name:"SessionEnd", reason:"other"}' \
    | env -u SECOND_BRAIN_VAULT bash "$HOOK" 2>&1)"; rc=$?
  assert_eq "$rc" "0" "unconfigured hook exits 0 (silent no-op)"
  assert_eq "$out" ""  "unconfigured hook prints nothing"
  assert_no_path "$(dirname "$t")/raw"   "unconfigured hook writes no raw/"
  assert_no_path "$(dirname "$t")/inbox" "unconfigured hook writes no inbox/"
}

test_noop_when_vault_empty_arg() {
  local sid t cwd out rc
  sid="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
  t="$(new_dir)/t.jsonl"; fixture_realistic "$t"; cwd="$(new_dir)"
  # hooks.json passes "" as $1 when vault_path is unset → must no-op exactly like the unset case.
  out="$(jq -nc --arg sid "$sid" --arg t "$t" --arg cwd "$cwd" \
    '{session_id:$sid, transcript_path:$t, cwd:$cwd, hook_event_name:"SessionEnd", reason:"other"}' \
    | env -u SECOND_BRAIN_VAULT bash "$HOOK" "" 2>&1)"; rc=$?
  assert_eq "$rc" "0" "empty-arg hook exits 0 (silent no-op)"
  assert_eq "$out" ""  "empty-arg hook prints nothing"
  assert_no_path "$(dirname "$t")/raw"   "empty-arg hook writes no raw/"
  assert_no_path "$(dirname "$t")/inbox" "empty-arg hook writes no inbox/"
}

# --- month-split regression: all versions of a sid anchor to ONE dir ---
fixture_dated() {   # $1=file  $2=ISO-8601 timestamp
  {
    printf '%s\n' '{"type":"last-prompt","sessionId":"x"}'
    printf '%s\n' "{\"type\":\"user\",\"timestamp\":\"$2\",\"message\":\"hi\"}"
  } > "$1"
}

test_split_month_versions() {
  local vault sid cwd m1 v1 v2 dir
  vault="$(new_dir)"; sid="abababab-abab-abab-abab-abababababab"; cwd="$(new_dir)"
  m1="$(date -u +%Y-%m)"
  # V1: no timestamps → captured under the capture-time month ($m1).
  v1="$vault/v1.jsonl"; fixture_stub "$v1"
  run_hook "$vault" "$sid" "$v1" "$cwd"
  # V2: a real timestamp in a DIFFERENT month → must anchor to V1's dir, not split.
  v2="$vault/v2.jsonl"; fixture_dated "$v2" "2020-01-15T10:00:00.000Z"
  run_hook "$vault" "$sid" "$v2" "$cwd"
  dir="$vault/raw/SessionEnd/$m1"
  assert_eq "$(ls "$dir/$sid".*.jsonl 2>/dev/null | wc -l | tr -d ' ')" "2" "both versions anchored to one dir ($m1)"
  assert_no_path "$vault/raw/SessionEnd/2020-01" "no split into the timestamp-derived month"
  assert_eq "$(ls "$dir/$sid".metadata.json 2>/dev/null | wc -l | tr -d ' ')" "1" "single metadata.json"
  assert_eq "$(ls "$vault/inbox/"*"-$sid.md" 2>/dev/null | wc -l | tr -d ' ')" "1" "single inbox pointer"
}

# --- runner (bash 3.2: no mapfile/arrays) ---
if [ "$#" -eq 0 ]; then set -- $(declare -F | awk '{print $3}' | grep '^test_' | sort); fi
for _t in "$@"; do "$_t"; done
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
