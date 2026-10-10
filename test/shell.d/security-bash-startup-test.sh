#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

cat >"$test_tmp/entrypoint" <<SH
#!/bin/bash -p
source "$ROOT/bin/omarchy-security-functions"
omarchy_security_require_privileged_bash_startup
SH
chmod +x "$test_tmp/entrypoint"

"$test_tmp/entrypoint" || fail "a script started as bash -p passes the startup check"
( "$test_tmp/entrypoint" ) || fail "the startup check passes from a subshell"
pass "a script started as bash -p passes the startup check"

if /usr/bin/bash -c "set -p; source '$ROOT/bin/omarchy-security-functions'; omarchy_security_require_privileged_bash_startup"; then
  fail "bash that only turned -p on later is rejected"
fi
if /usr/bin/bash "$test_tmp/entrypoint"; then
  fail "a script not started with -p is rejected"
fi
pass "bash not started with -p is rejected"

# arch-chroot runs the installer in a new PID namespace under the outer /proc,
# so the caller's own PID is not the number /proc knows it by.
in_new_pid_namespace=(unshare --user --map-root-user --fork --pid)
if "${in_new_pid_namespace[@]}" /usr/bin/true 2>/dev/null; then
  "${in_new_pid_namespace[@]}" /usr/bin/bash -c "for i in {1..50}; do /usr/bin/true; done; '$test_tmp/entrypoint'; exit" </dev/null ||
    fail "the startup check passes in a new PID namespace under the outer /proc"
  if "${in_new_pid_namespace[@]}" /usr/bin/bash -c "/usr/bin/bash '$test_tmp/entrypoint'; exit" </dev/null; then
    fail "a script not started with -p is rejected in a new PID namespace"
  fi
  pass "the startup check sees its caller in a new PID namespace, as under arch-chroot"
else
  skip "a new PID namespace needs unprivileged user namespaces"
fi
