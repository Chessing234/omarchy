#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

units=(
  systemd-pcrphase-sysinit.service
  systemd-pcrphase.service
  systemd-pcrmachine.service
  systemd-pcrfs-root.service
  'systemd-pcrfs@.service'
)

for unit in "${units[@]}"; do
  drop_in="$ROOT/etc/systemd/system/${unit}.d/10-omarchy-no-force-reboot.conf"
  [[ -f $drop_in ]] || fail "shipped drop-in exists for $unit"
  grep -qxF 'FailureAction=none' "$drop_in" ||
    fail "drop-in clears reboot-force for $unit"
  grep -qxF '[Unit]' "$drop_in" ||
    fail "FailureAction override is under [Unit] for $unit"
done

pass "PCR measurement units ship FailureAction=none drop-ins"

migration="$ROOT/migrations/1789561000.sh"
[[ -f $migration ]] || fail "migration that applies the drop-ins exists"

# omarchy-settings installs the drop-ins; the migration only reloads systemd.
test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

mkdir -p "$test_tmp/bin"
cat >"$test_tmp/bin/systemctl" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_TMP/systemctl.log"
exit "${SYSTEMCTL_STATUS:-0}"
STUB
cat >"$test_tmp/bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
cat >"$test_tmp/bin/omarchy-state" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$TEST_TMP/state.log"
STUB
chmod +x "$test_tmp/bin"/*

PATH="$test_tmp/bin:$PATH" TEST_TMP="$test_tmp" bash -euo pipefail "$migration" >/dev/null

grep -qxF 'daemon-reload' "$test_tmp/systemctl.log" ||
  fail "migration runs systemctl daemon-reload"
[[ ! -e $test_tmp/state.log ]] ||
  fail "successful reload does not set reboot-required"

pass "migration reloads systemd so the drop-ins apply without reboot"

PATH="$test_tmp/bin:$PATH" TEST_TMP="$test_tmp" SYSTEMCTL_STATUS=1 bash -euo pipefail "$migration" >/dev/null

grep -qxF 'set reboot-required' "$test_tmp/state.log" ||
  fail "failed reload asks for a reboot"

pass "migration asks for a reboot when systemd cannot reload"
