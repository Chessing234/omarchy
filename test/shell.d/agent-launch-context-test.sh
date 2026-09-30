#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
env_log="$test_tmp/env.log"
mkdir -p "$mock_bin" "$test_home/.config/omarchy/defaults" "$test_home/Work/project"
printf 'claude\n' >"$test_home/.config/omarchy/defaults/agent"

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$mock_bin/claude" <<'SH'
#!/bin/bash
{
  printf 'agent:%s\n' "${OMARCHY_AGENT-}"
  printf 'cwd:%s\n' "${OMARCHY_AGENT_CWD-}"
} >"$OMARCHY_TEST_ENV_LOG"
SH

chmod +x "$mock_bin/omarchy-cmd-missing" "$mock_bin/claude"

HOME="$test_home" PATH="$mock_bin:$ROOT/bin:$PATH" \
  OMARCHY_TEST_ENV_LOG="$env_log" \
  bash -c 'cd "$1" && omarchy-agent --inline' bash "$test_home/Work/project"

grep -Fx 'agent:claude' "$env_log" ||
  fail "launched agent does not see OMARCHY_AGENT" "$(cat "$env_log")"
grep -Fx "cwd:$test_home/Work/project" "$env_log" ||
  fail "launched agent does not see OMARCHY_AGENT_CWD" "$(cat "$env_log")"
pass "launched agent receives OMARCHY_AGENT and OMARCHY_AGENT_CWD"
