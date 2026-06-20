#!/usr/bin/env bash
# Self-test for validate-filing.sh: it must FAIL an unfiled vault and PASS a
# correctly-filed hand-made one. Zero deps (bash 3.2 + jq). Run:
#   bash plugins/second-brain/tests/librarian/test-tooling.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE="$HERE/validate-filing.sh"
MKFIX="$HERE/make-fixtures.sh"
pass=0; fail=0
ok(){ pass=$((pass+1)); }
no(){ printf 'FAIL: %s\n' "$1" >&2; fail=$((fail+1)); }
newd(){ local d; d="$(mktemp -d)"; (cd "$d" && pwd); }

# A: an unfiled vault (fixtures present, nothing filed) must FAIL validation.
A="$(newd)"; ( cd "$A" && git init -q && git config user.email t@t && git config user.name t )
bash "$MKFIX" "$A" >/dev/null
if bash "$VALIDATE" "$A" >/dev/null 2>&1; then no "validate PASSED an unfiled vault (should fail)"; else ok; fi

# B: a minimal correctly-filed vault must PASS validation.
B="$(newd)"; ( cd "$B" && git init -q && git config user.email t@t && git config user.name t )
mkdir -p "$B/inbox" "$B/raw/SessionEnd/2026-06" "$B/journal/2026-06" "$B/wiki/nginx"
: > "$B/inbox/.keep"; : > "$B/raw/.keep"
SID="11111111-1111-1111-1111-111111111111"
cat > "$B/raw/SessionEnd/2026-06/$SID.metadata.json" <<EOF
{"session_id":"$SID","project":"webapp","start_date":"2026-06-18","filed_at":"2026-06-19","filed":["journal/2026-06/2026-06-18.md","wiki/nginx/gzip.md"]}
EOF
cat > "$B/raw/SessionEnd/2026-06/$SID.abcd1234.jsonl" <<EOF
{"type":"user","timestamp":"2026-06-18T09:00:00.000Z","message":{"role":"user","content":"How do I enable gzip in nginx?"}}
EOF
cat > "$B/journal/2026-06/2026-06-18.md" <<EOF
## webapp

- Configured nginx gzip. [[gzip]]

<!-- sessions: $SID -->
EOF
cat > "$B/wiki/nginx/gzip.md" <<EOF
---
summary: How to enable gzip in nginx.
source: ["raw/SessionEnd/2026-06/$SID.abcd1234.jsonl"]
created: 2026-06-18
updated: 2026-06-18
---
Enable with gzip on; in the http block.
EOF
cat > "$B/wiki/nginx/index.md" <<EOF
---
tags: [moc]
---
# nginx
- [[gzip]] — enabling gzip compression.
EOF
cat > "$B/wiki/index.md" <<EOF
---
tags: [moc]
---
# Wiki
- [[nginx/index|nginx]]
EOF
cat > "$B/index.md" <<EOF
# Second Brain
- journal/
- [[wiki/index|wiki]]
EOF
( cd "$B" && git add -A && git commit -q -m "feat(nginx): file webapp session" )
if bash "$VALIDATE" "$B" >/dev/null 2>&1; then ok; else no "validate FAILED a correctly-filed vault (should pass)"; fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
