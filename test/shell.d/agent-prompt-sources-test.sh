#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mock_bin="$test_tmp/bin"
test_home="$test_tmp/home"
agent_log="$test_tmp/agent.log"
mkdir -p "$mock_bin" "$test_home/.config/omarchy/defaults"
printf 'claude\n' >"$test_home/.config/omarchy/defaults/agent"

cat >"$mock_bin/omarchy-agent" <<'SH'
#!/bin/bash
printf '%s\0' "$@" >"$OMARCHY_TEST_AGENT_LOG"
SH
chmod +x "$mock_bin/omarchy-agent"

run_prompt() {
  HOME="$test_home" PATH="$mock_bin:$ROOT/bin:$PATH" \
    OMARCHY_TEST_AGENT_LOG="$agent_log" \
    "$@"
}

: >"$agent_log"
printf 'review this; echo $(whoami)\n' | run_prompt "$ROOT/bin/omarchy-agent-prompt" -
grep -Fz $'--prompt\0review this; echo $(whoami)' "$agent_log" >/dev/null ||
  fail "stdin prompt (-) does not reach omarchy-agent" "$(tr '\0' ' ' <"$agent_log")"
pass "stdin prompt (-) reaches omarchy-agent"

cat >"$mock_bin/wl-paste" <<'SH'
#!/bin/bash
printf 'clipboard body; rm -rf /'
SH
chmod +x "$mock_bin/wl-paste"

: >"$agent_log"
run_prompt "$ROOT/bin/omarchy-agent-prompt" --clipboard
grep -Fz $'--prompt\0clipboard body; rm -rf /' "$agent_log" >/dev/null ||
  fail "--clipboard does not reach omarchy-agent" "$(tr '\0' ' ' <"$agent_log")"
pass "--clipboard reaches omarchy-agent"

cat >"$mock_bin/wl-paste" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$mock_bin/wl-paste"
if run_prompt "$ROOT/bin/omarchy-agent-prompt" --clipboard 2>"$test_tmp/err"; then
  fail "empty clipboard still launched an agent"
fi
grep -Fq 'Clipboard is empty' "$test_tmp/err" ||
  fail "empty clipboard does not explain the failure" "$(cat "$test_tmp/err")"
pass "empty clipboard is refused"

: >"$agent_log"
run_prompt "$ROOT/bin/omarchy-agent-prompt" --inline "keep argv prompts"
grep -Fz $'--inline\0--prompt\0keep argv prompts' "$agent_log" >/dev/null ||
  fail "argv prompts still work alongside the new sources" "$(tr '\0' ' ' <"$agent_log")"
pass "argv prompts still work alongside the new sources"
