#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
dispatch_log="$test_tmp/dispatch.log"
launch_log="$test_tmp/launch.log"
mkdir -p "$mock_bin" "$test_home/.config/omarchy/agents" "$test_home/.config/omarchy/defaults"

printf 'claude\n' >"$test_home/.config/omarchy/defaults/agent"

cat >"$mock_bin/omarchy-cmd-missing" <<'SH'
#!/bin/bash
exit 1
SH

cat >"$mock_bin/omarchy-launch-tui" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_LAUNCH_LOG"
SH

cat >"$mock_bin/claude" <<'SH'
#!/bin/bash
printf '%s\0' claude "$@" >"$OMARCHY_TEST_LAUNCH_LOG"
SH

chmod +x "$mock_bin/omarchy-cmd-missing" "$mock_bin/omarchy-launch-tui" "$mock_bin/claude"

run_agent() {
  HOME="$test_home" PATH="$mock_bin:$ROOT/bin:$PATH" \
    OMARCHY_TEST_LAUNCH_LOG="$launch_log" \
    OMARCHY_TEST_DISPATCH_LOG="$dispatch_log" \
    "$ROOT/bin/omarchy-agent" "$@"
}

# No dispatcher: prompted launch still reaches the harness.
: >"$launch_log"
run_agent --inline --prompt 'review this; echo $(whoami)'
grep -Fz $'claude\0--permission-mode\0auto\0--\0review this; echo $(whoami)' "$launch_log" >/dev/null ||
  fail "prompted launch without a dispatcher still reaches the default harness" "$(tr '\0' ' ' <"$launch_log")"
pass "prompted launch without a dispatcher still reaches the default harness"

# Promptless launch never consults a dispatcher even when one is installed.
cat >"$test_home/.config/omarchy/agents/request-dispatch" <<'SH'
#!/bin/bash
printf 'ran\n' >>"$OMARCHY_TEST_DISPATCH_LOG"
exit 0
SH
chmod +x "$test_home/.config/omarchy/agents/request-dispatch"
: >"$dispatch_log"
: >"$launch_log"
run_agent --inline
[[ ! -s $dispatch_log ]] || fail "promptless launch consulted the request dispatcher"
grep -Fz $'claude\0--permission-mode\0auto' "$launch_log" >/dev/null ||
  fail "promptless launch still reaches the default harness" "$(tr '\0' ' ' <"$launch_log")"
pass "promptless launch ignores the request dispatcher"

# A dispatcher that accepts owns the request: prompt on stdin, never on argv.
cat >"$test_home/.config/omarchy/agents/request-dispatch" <<'SH'
#!/bin/bash
prompt=$(cat)
{
  printf 'argv:'
  printf ' %q' "$@"
  printf '\n'
  printf 'prompt:%s\n' "$prompt"
} >>"$OMARCHY_TEST_DISPATCH_LOG"
# Refuse to claim if the prompt leaked onto argv.
for arg in "$@"; do
  [[ $arg == *'$(whoami)'* ]] && exit 2
done
exit 0
SH
chmod +x "$test_home/.config/omarchy/agents/request-dispatch"
: >"$dispatch_log"
: >"$launch_log"
run_agent --inline --prompt 'review this; echo $(whoami)'
grep -Fq 'argv: --fallback-agent claude --cwd' "$dispatch_log" ||
  fail "dispatcher receives fallback agent and cwd on argv" "$(cat "$dispatch_log")"
grep -Fq 'prompt:review this; echo $(whoami)' "$dispatch_log" ||
  fail "dispatcher receives the prompt on stdin" "$(cat "$dispatch_log")"
[[ ! -s $launch_log ]] ||
  fail "accepted dispatcher still launched the fallback harness" "$(tr '\0' ' ' <"$launch_log")"
pass "accepted dispatcher owns the prompted request"

# A clean decline falls through to the harness.
cat >"$test_home/.config/omarchy/agents/request-dispatch" <<'SH'
#!/bin/bash
cat >/dev/null
exit 3
SH
chmod +x "$test_home/.config/omarchy/agents/request-dispatch"
: >"$launch_log"
run_agent --inline --prompt 'please handle'
grep -Fz $'claude\0--permission-mode\0auto\0--\0please handle' "$launch_log" >/dev/null ||
  fail "declined dispatcher does not fall through to the harness" "$(tr '\0' ' ' <"$launch_log")"
pass "declined dispatcher falls through to the default harness"

# Other-owned or non-executable hooks are ignored.
cat >"$test_home/.config/omarchy/agents/request-dispatch" <<'SH'
#!/bin/bash
printf 'ran\n' >>"$OMARCHY_TEST_DISPATCH_LOG"
exit 0
SH
chmod a-x "$test_home/.config/omarchy/agents/request-dispatch"
: >"$dispatch_log"
: >"$launch_log"
run_agent --inline --prompt 'noexec'
[[ ! -s $dispatch_log ]] || fail "non-executable dispatcher was consulted"
grep -Fz $'claude\0--permission-mode\0auto\0--\0noexec' "$launch_log" >/dev/null ||
  fail "non-executable dispatcher blocked the fallback" "$(tr '\0' ' ' <"$launch_log")"
pass "non-executable dispatcher is ignored"
