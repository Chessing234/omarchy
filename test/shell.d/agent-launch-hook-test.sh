#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
hook_log="$test_tmp/hook.log"
harness_log="$test_tmp/harness.log"
mkdir -p "$mock_bin" "$test_home/.config/omarchy/defaults" "$test_home/.config/omarchy/hooks" \
  "$test_home/Work/demo"
printf 'pi\n' >"$test_home/.config/omarchy/defaults/agent"

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
exit 1
SH
cat >"$mock_bin/pi" <<'SH'
#!/bin/bash
printf 'started\n' >>"$OMARCHY_TEST_HARNESS_LOG"
SH
chmod +x "$mock_bin/omarchy-cmd-missing" "$mock_bin/pi"

cat >"$test_home/.config/omarchy/hooks/agent-launch" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >>"$OMARCHY_TEST_HOOK_LOG"
SH
chmod +x "$test_home/.config/omarchy/hooks/agent-launch"

HOME="$test_home" PATH="$mock_bin:$ROOT/bin:$PATH" OMARCHY_TEST_HOOK_LOG="$hook_log" \
  OMARCHY_TEST_HARNESS_LOG="$harness_log" \
  bash -c 'cd "$1" && omarchy-agent --inline' bash "$test_home/Work/demo"

grep -Fxq "pi $test_home/Work/demo" "$hook_log" ||
  fail "agent-launch hook did not see harness and cwd" "$(cat "$hook_log" 2>/dev/null)"
pass "agent-launch hook runs with harness and cwd"

# A failing hook must not prevent the agent from starting.
cat >"$test_home/.config/omarchy/hooks/agent-launch" <<'SH'
#!/bin/bash
exit 7
SH
chmod +x "$test_home/.config/omarchy/hooks/agent-launch"
: >"$harness_log"
HOME="$test_home" PATH="$mock_bin:$ROOT/bin:$PATH" OMARCHY_TEST_HARNESS_LOG="$harness_log" \
  bash -c 'cd "$1" && omarchy-agent --inline' bash "$test_home/Work/demo" ||
  fail "a failing agent-launch hook blocks the harness"
if [[ $(cat "$harness_log") != "started" ]]; then
  fail "a failing agent-launch hook must still execute the harness"
fi
pass "a failing agent-launch hook does not block the harness"
