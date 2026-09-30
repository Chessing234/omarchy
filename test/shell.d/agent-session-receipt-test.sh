#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
runtime="$test_tmp/runtime"
mkdir -p "$mock_bin" "$test_home/.config/omarchy/defaults" "$test_home/Work/demo" "$runtime"
printf 'codex\n' >"$test_home/.config/omarchy/defaults/agent"

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
exit 1
SH
cat >"$mock_bin/omarchy-launch-tui" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$mock_bin/codex" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$mock_bin/omarchy-cmd-missing" "$mock_bin/omarchy-launch-tui" "$mock_bin/codex"

HOME="$test_home" PATH="$mock_bin:$ROOT/bin:$PATH" XDG_RUNTIME_DIR="$runtime" \
  bash -c 'cd "$1" && omarchy-agent --inline' bash "$test_home/Work/demo"

receipt="$runtime/omarchy/agent-session.env"
[[ -f $receipt ]] || fail "agent launch does not write a session receipt"
# shellcheck disable=SC1090
source "$receipt"
[[ $OMARCHY_AGENT == "codex" ]] || fail "receipt agent is wrong: $OMARCHY_AGENT"
[[ $OMARCHY_AGENT_CWD == "$test_home/Work/demo" ]] || fail "receipt cwd is wrong: $OMARCHY_AGENT_CWD"
[[ $OMARCHY_AGENT_INLINE == "true" ]] || fail "receipt inline flag is wrong: $OMARCHY_AGENT_INLINE"
[[ -n $OMARCHY_AGENT_STARTED_AT ]] || fail "receipt is missing a start timestamp"
pass "agent launch writes a sourcable session receipt"
