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

expect_args() {
  local description=$1
  shift
  if ! python3 - "$agent_log" "$@" <<'PY'
import sys
got = [part.decode() for part in open(sys.argv[1], "rb").read().split(b"\0") if part]
want = sys.argv[2:]
if got != want:
  raise SystemExit(f"got {got!r} want {want!r}")
PY
  then
    fail "$description" "$(tr '\0' ' ' <"$agent_log")"
  fi
  pass "$description"
}

: >"$agent_log"
printf 'review this; echo $(whoami)\n' | run_prompt "$ROOT/bin/omarchy-agent-prompt" -
expect_args "stdin prompt (-) reaches omarchy-agent" --prompt 'review this; echo $(whoami)'

cat >"$mock_bin/wl-paste" <<'SH'
#!/bin/bash
printf 'clipboard body; rm -rf /'
SH
chmod +x "$mock_bin/wl-paste"

: >"$agent_log"
run_prompt "$ROOT/bin/omarchy-agent-prompt" --clipboard
expect_args "--clipboard reaches omarchy-agent" --prompt 'clipboard body; rm -rf /'

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
expect_args "argv prompts still work alongside the new sources" --inline --prompt "keep argv prompts"
