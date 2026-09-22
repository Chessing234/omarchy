#!/bin/bash

# omarchy-update-stay-awake must never call bare `sudo -v` (hangs under
# passwordless NOPASSWD with verifypw=all, and under unattended update PTYs).

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

script="$ROOT/bin/omarchy-update-stay-awake"
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
runtime_dir="$test_tmp/runtime"
home="$test_tmp/home"
sudo_log="$test_tmp/sudo.log"
pkexec_log="$test_tmp/pkexec.log"
inhibit_marker="$test_tmp/inhibit-ran"
mkdir -p "$stub_bin" "$runtime_dir" "$home/.local/state/omarchy/indicators"

cat >"$stub_bin/omarchy-cmd-present" <<'SH'
#!/bin/bash
[[ $1 == "systemd-inhibit" ]]
SH

cat >"$stub_bin/omarchy-toggle-idle" <<'SH'
#!/bin/bash
exit 0
SH

cat >"$stub_bin/systemd-inhibit" <<SH
#!/bin/bash
touch "$inhibit_marker"
exit 0
SH

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$SUDO_LOG"
# A bare -v would hang for passwd_timeout on real systems under verifypw=all.
if [[ $1 == "-v" ]]; then
  echo "bare sudo -v must not be used" >&2
  exit 99
fi
if [[ $1 == "-n" && $2 == "true" ]]; then
  [[ ${SUDO_N_OK:-1} == 1 ]]
  exit $?
fi
[[ $1 != "-n" ]] || shift
exec "$@"
SH

cat >"$stub_bin/pkexec" <<'SH'
#!/bin/bash
printf 'pkexec %s\n' "$*" >>"$PKEXEC_LOG"
exec "$@"
SH

chmod +x "$stub_bin"/*

wait_for() {
  local file="$1"
  local attempt

  for (( attempt = 0; attempt < 100; attempt++ )); do
    [[ -e $file ]] && return 0
    sleep 0.02
  done
  return 1
}

run_start() {
  : >"$sudo_log"
  : >"$pkexec_log"
  rm -f "$inhibit_marker"
  rm -rf "$runtime_dir/omarchy-update-stay-awake"
  env -u OMARCHY_UPDATE_UNATTENDED "$@" \
    PATH="$stub_bin:$PATH" \
    HOME="$home" \
    XDG_RUNTIME_DIR="$runtime_dir" \
    SUDO_LOG="$sudo_log" \
    PKEXEC_LOG="$pkexec_log" \
    bash "$script" start
  # Inhibit is backgrounded; wait until the stub has been entered.
  wait_for "$inhibit_marker" || fail "stay-awake starts systemd-inhibit" "$(cat "$sudo_log"; echo ---; cat "$pkexec_log")"
}

# Passwordless / cached ticket: non-interactive probe succeeds → sudo inhibit.
run_start SUDO_N_OK=1
grep -qF 'sudo -n true' "$sudo_log" || fail "probes sudo with -n true" "$(cat "$sudo_log")"
grep -qF 'sudo systemd-inhibit' "$sudo_log" ||
  fail "runs inhibit via sudo when probe succeeds" "$(cat "$sudo_log")"
[[ ! -s $pkexec_log ]] || fail "does not use pkexec when sudo -n works" "$(cat "$pkexec_log")"
! grep -qE 'sudo -v($| )' "$sudo_log" || fail "must never call bare sudo -v" "$(cat "$sudo_log")"
pass "passwordless sudo uses non-interactive probe then sudo inhibit"

# No sudo ticket, unattended update: never block on pkexec / password prompt.
# Inhibit still runs as the user (empty runner) so sleep blocking degrades safely.
run_start SUDO_N_OK=0 OMARCHY_UPDATE_UNATTENDED=1
grep -qF 'sudo -n true' "$sudo_log" || fail "unattended still probes sudo -n" "$(cat "$sudo_log")"
! grep -qF 'sudo systemd-inhibit' "$sudo_log" ||
  fail "unattended does not sudo inhibit without a ticket" "$(cat "$sudo_log")"
[[ ! -s $pkexec_log ]] || fail "unattended does not fall back to pkexec" "$(cat "$pkexec_log")"
pass "unattended update skips privileged inhibit instead of hanging"

# No sudo ticket, attended: fall back to pkexec (existing non-tty path).
run_start SUDO_N_OK=0
grep -qF 'pkexec systemd-inhibit' "$pkexec_log" ||
  fail "attended without sudo ticket uses pkexec" "$(cat "$pkexec_log"; echo ---; cat "$sudo_log")"
! grep -qE 'sudo -v($| )' "$sudo_log" || fail "attended path must not call bare sudo -v" "$(cat "$sudo_log")"
pass "attended without sudo ticket uses pkexec without sudo -v"
