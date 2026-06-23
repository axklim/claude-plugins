#!/usr/bin/env bash
# Regression harness for dev-workflow local-only support (issue #10).
# Verifies the git recipes the local-only skill paths document. No remote, no gh.
set -u

pass=0; fail=0
check() { # check "label" <command...>
  local label="$1"; shift
  if "$@"; then echo "PASS: $label"; pass=$((pass+1));
  else echo "FAIL: $label"; fail=$((fail+1)); fi
}

# The canonical trunk-resolution snippet (must match the skills verbatim in spirit).
resolve_trunk() {
  base=""; trunk=""
  for ref in origin/main origin/master refs/heads/main refs/heads/master; do
    if git rev-parse --verify --quiet "$ref" >/dev/null; then
      base="$ref"; trunk="${ref##*/}"; break
    fi
  done
}

# Build a repo whose trunk is $2, with a feature branch 3 commits ahead. No remote.
setup_repo() { # setup_repo <dir> <trunk-name>
  local dir="$1" trunkname="$2"
  git init -q -b "$trunkname" "$dir"
  ( cd "$dir"
    git config user.email t@example.com; git config user.name tester
    printf 'base\n' > f.txt; git add f.txt; git commit -qm "init"
    git checkout -q -b feature
    printf 'a\n' >> f.txt; git commit -qam "wip a"
    printf 'b\n' >> f.txt; git commit -qam "wip b"
    printf 'c\n' >> f.txt; git commit -qam "wip c"
  )
}

# NOTE: the per-scenario work must NOT run inside a ( … ) subshell — `check`
# increments pass/fail, and a subshell's increments would be lost. Use cd + cd back.
root=$(pwd)

# --- Scenarios A (trunk=main) and B (trunk=master): no remote, trunk exists ---
for trunkname in main master; do
  d=$(mktemp -d)
  setup_repo "$d" "$trunkname"
  cd "$d"

  resolve_trunk
  check "[$trunkname] resolve_trunk picks local $trunkname" test "$trunk" = "$trunkname"
  check "[$trunkname] base is local ref" test "$base" = "refs/heads/$trunkname"

  # restructure-commits local recipe: squash to merge-base, rebase onto <base>, no push.
  mb=$(git merge-base "$base" HEAD)
  git reset --soft "$mb"
  git commit -qm "feat: squashed feature work"
  git rebase -q "$base"
  check "[$trunkname] feature is 1 commit ahead of trunk" \
    test "$(git rev-list --count "$trunk"..HEAD)" = "1"
  check "[$trunkname] trunk is an ancestor (rebased cleanly)" \
    test "$(git rev-list --count HEAD.."$trunk")" = "0"
  new_tip=$(git rev-parse HEAD)

  # merge local recipe: switch trunk, ff-only, delete branch.
  feature=$(git branch --show-current)
  resolve_trunk
  git switch -q "$trunk"
  git merge --ff-only -q "$feature"
  git branch -q -d "$feature"
  check "[$trunkname] trunk fast-forwarded to feature tip" \
    test "$(git rev-parse "$trunk")" = "$new_tip"
  check "[$trunkname] feature branch deleted" \
    test -z "$(git branch --list "$feature")"

  cd "$root"; rm -rf "$d"
done

# --- Scenario C: no trunk at all (repro) -> resolution must yield nothing ---
d=$(mktemp -d)
git init -q -b feature "$d"   # initial branch is 'feature'; no main/master ever created
cd "$d"
git config user.email t@example.com; git config user.name tester
printf 'x\n' > f.txt; git add f.txt; git commit -qm "root on feature"
resolve_trunk
check "[no-trunk] resolve_trunk yields empty base (skill must halt)" test -z "$base"
cd "$root"; rm -rf "$d"

echo "----"
echo "passed: $pass  failed: $fail"
[ "$fail" -eq 0 ]
