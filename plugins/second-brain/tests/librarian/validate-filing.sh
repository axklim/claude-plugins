#!/usr/bin/env bash
# Assert the librarian output contract holds in <vault>. Zero deps (bash 3.2 + jq).
# Usage: validate-filing.sh <vault>   → exit 0 iff all structural invariants pass.
# SCOPE: acceptance gate for a SIGNAL-BEARING batch (the fixtures always produce >=1
# journaled session and >=1 wiki note). NOT a general post-filing invariant: a real
# batch of only-noise sessions (where the librarian may legitimately write nothing)
# would fail checks 2/5/7 — that degenerate case is out of scope for this harness.
set -uo pipefail
V="${1:?usage: validate-filing.sh <vault>}"
pass=0; fail=0
ok(){ pass=$((pass+1)); }
no(){ printf 'FAIL: %s\n' "$1" >&2; fail=$((fail+1)); }

# 1. inbox emptied (only .keep remains)
if [ -z "$(find "$V/inbox" -type f ! -name .keep 2>/dev/null)" ]; then ok; else no "inbox still has pointers (not all filed)"; fi

# 2. at least one journal day-file exists
jfiles="$(find "$V/journal" -type f -name '20*-*-*.md' 2>/dev/null)"
if [ -n "$jfiles" ]; then ok; else no "no journal/<month>/<date>.md produced"; fi

# 3. every journal day-file: no '# ' H1, has a '## ' heading, no relative links, has a sessions footer
jbad=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  grep -q '^# '  "$f" && jbad=1                       # H1 forbidden (filename is the title)
  grep -q '^## ' "$f" || jbad=1                       # must group by project
  grep -q '\[\[\.\./' "$f" && jbad=1                  # no relative wikilinks
  grep -q '<!-- sessions:' "$f" || jbad=1             # must carry the provenance footer
done < <(find "$V/journal" -type f -name '20*-*-*.md' 2>/dev/null)
[ "$jbad" -eq 0 ] && ok || no "a journal file has a '# ' H1, a relative link, or lacks a '## ' heading / sessions footer"

# 4. wiki/index.md exists, non-empty, is an MOC
if [ -s "$V/wiki/index.md" ] && grep -q 'moc' "$V/wiki/index.md"; then ok; else no "wiki/index.md missing/empty or not tagged moc"; fi

# 5. there is at least one wiki note, and EVERY note carries all four required frontmatter keys
notes="$(find "$V/wiki" -type f -name '*.md' ! -name 'index.md' ! -name '_seedlings.md' 2>/dev/null)"
if [ -z "$notes" ]; then
  no "no wiki notes produced"
else
    note_bad=0
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      grep -q '^summary:' "$f" && grep -q '^source:' "$f" && grep -q '^created:' "$f" && grep -q '^updated:' "$f" || note_bad=1
    done < <(find "$V/wiki" -type f -name '*.md' ! -name 'index.md' ! -name '_seedlings.md' 2>/dev/null)
    [ "$note_bad" -eq 0 ] && ok || no "a wiki note is missing a required frontmatter key (summary/source/created/updated)"
fi

# 6. root index.md exists
[ -s "$V/index.md" ] && ok || no "root index.md missing/empty"

# 7. HEAD commit touches journal/ and wiki/
touched="$( ( cd "$V" && git show --name-only --format= HEAD 2>/dev/null ) )"
if printf '%s\n' "$touched" | grep -q '^journal/' && printf '%s\n' "$touched" | grep -q '^wiki/'; then ok; else no "HEAD commit does not touch journal/ and wiki/"; fi

# 8. every raw metadata.json records provenance: filed_at set + filed is an array
mbad=0
while IFS= read -r m; do
  [ -n "$m" ] || continue
  fat="$(jq -r '.filed_at // empty' "$m" 2>/dev/null)"
  isarr="$(jq -r '(.filed | type) == "array"' "$m" 2>/dev/null)"
  { [ -n "$fat" ] && [ "$isarr" = "true" ]; } || mbad=1
done < <(find "$V/raw" -type f -name '*.metadata.json' 2>/dev/null)
[ "$mbad" -eq 0 ] && ok || no "a raw metadata.json lacks .filed_at or a .filed array (provenance)"

# 9. journal footer-completeness: each day-file's <!-- sessions: --> set == the sids whose raw
#    jsonl has at least one message timestamped that day. The one deterministic journal check.
fcbad=0
while IFS= read -r f; do
  [ -n "$f" ] || continue
  d="$(basename "$f" .md)"                            # YYYY-MM-DD
  footer="$(grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}' "$f" | sort -u)"
  expected=""
  while IFS= read -r j; do
    [ -n "$j" ] || continue
    sid="$(basename "$j" | sed 's/\..*//')"           # sid = filename up to first dot
    if jq -e --arg d "$d" 'select(((.timestamp // "") | startswith($d))) | 1' "$j" >/dev/null 2>&1; then
      expected="$expected$sid"$'\n'
    fi
  done < <(find "$V/raw" -type f -name '*.jsonl' 2>/dev/null)
  expected="$(printf '%s' "$expected" | sed '/^$/d' | sort -u)"
  [ "$footer" = "$expected" ] || fcbad=1
done < <(find "$V/journal" -type f -name '20*-*-*.md' 2>/dev/null)
[ "$fcbad" -eq 0 ] && ok || no "a journal day-file footer != the sessions touching that day"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
