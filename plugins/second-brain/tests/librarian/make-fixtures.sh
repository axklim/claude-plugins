#!/usr/bin/env bash
# Populate <vault> with realistic synthetic raw/ + inbox/ sessions for the
# librarian acceptance run. Mirrors Job A's data contract. Zero deps (bash + jq).
# Usage: make-fixtures.sh <vault>
set -uo pipefail
V="${1:?usage: make-fixtures.sh <vault>}"
mkdir -p "$V/raw/SessionEnd/2026-06" "$V/inbox"
: > "$V/raw/.keep"; : > "$V/inbox/.keep"

# helper: write one raw session (sid, project, start_date, hash, transcript-file-content-cmd)
emit() {
  local sid="$1" project="$2" start="$3" hash="$4"; shift 4
  local dir="$V/raw/SessionEnd/2026-06"
  "$@" > "$dir/$sid.$hash.jsonl"                                   # transcript lines via $@
  jq -nc --arg s "$sid" --arg p "$project" --arg d "$start" \
    '{session_id:$s, transcript_path:("/tmp/"+$s+".jsonl"), cwd:("/work/"+$p), hook_event_name:"SessionEnd", reason:"other"}' \
    > "$dir/$sid.$hash.hook.json"
  jq -nc --arg s "$sid" --arg p "$project" --arg d "$start" \
    '{session_id:$s, project:$p, start_date:$d}' > "$dir/$sid.metadata.json"
  cat > "$V/inbox/$start-$project-$sid.md" <<EOF
---
session_id: $sid
project: $project
start_date: $start
raw_dir: raw/SessionEnd/2026-06
---
EOF
}

line(){ jq -nc --arg t "$1" --arg ts "$2" --arg c "$3" '{type:$t, timestamp:$ts, message:{role:$t, content:$c}}'; }
# like line(), but content is an ARRAY of blocks (real assistant-turn shape): a text
# block plus tool_use + nested tool_result noise the librarian must ignore.
line_blocks(){ jq -nc --arg t "$1" --arg ts "$2" --arg x "$3" \
  '{type:$t, timestamp:$ts, message:{role:$t, content:[
    {type:"text", text:$x},
    {type:"tool_use", name:"Edit", input:{file_path:"nginx.conf"}},
    {type:"tool_result", content:[{type:"text", text:"applied"}]}
  ]}}'; }

# Session 1 + 2: same topic (nginx gzip) on 2026-06-18 → must MERGE into one wiki note.
s1(){ line user      2026-06-18T09:00:00.000Z "How do I enable gzip in nginx?"
      line_blocks assistant 2026-06-18T09:01:00.000Z "Set 'gzip on;' and gzip_types in the http block of nginx.conf."; }
s2(){ line user      2026-06-18T14:00:00.000Z "gzip is on but JSON isn't compressed."
      line assistant 2026-06-18T14:02:00.000Z "Add application/json to gzip_types; the default list omits it."; }
emit 11111111-1111-1111-1111-111111111111 webapp 2026-06-18 aaaa1111 s1
emit 22222222-2222-2222-2222-222222222222 webapp 2026-06-18 bbbb2222 s2

# Session 3: a DIFFERENT topic that SPANS two days → journal must post to both days.
s3(){ line user      2026-06-18T23:30:00.000Z "Add rate limiting to the widget-api."
      line assistant 2026-06-18T23:35:00.000Z "Use a token-bucket limiter keyed by client id."
      line user      2026-06-19T00:10:00.000Z "It rejects valid bursts."
      line assistant 2026-06-19T00:12:00.000Z "Raise the bucket capacity above the burst size."; }
emit 33333333-3333-3333-3333-333333333333 widget-api 2026-06-18 cccc3333 s3

echo "fixtures written to $V"
