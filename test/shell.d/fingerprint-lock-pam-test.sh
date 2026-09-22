#!/bin/bash
#
# Lock-screen fingerprint PAM must include the clamshell gate before
# pam_fprintd. A re-run of setup must keep writing that gate (not wipe a
# manually restored one). Privileged PAM writes are retargeted into a scratch
# tree so the suite never touches the host.

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT

pam_dir="$scratch/pam.d"
mkdir -p "$scratch/bin" "$pam_dir"

setup="$ROOT/bin/omarchy-setup-security-fingerprint"
setup_copy="$scratch/setup.sh"

# Fail loudly if the command stops naming its PAM directory the way this
# retarget expects, so the suite cannot pass without exercising the real paths.
occurrences=$(grep -Foc '/etc/pam.d' "$setup") || occurrences=0
(( occurrences >= 1 )) || fail "fingerprint setup names /etc/pam.d"
sed "s|/etc/pam.d|$pam_dir|g" "$setup" >"$setup_copy"
grep -Fq '/etc/pam.d' "$setup_copy" && fail "retargeted setup still names /etc/pam.d"
grep -Fq "$pam_dir" "$setup_copy" || fail "retargeted setup writes under the scratch PAM dir"
chmod +x "$setup_copy"

export CALL_LOG="$scratch/calls"
export PATH="$scratch/bin:$ROOT/bin:$PATH"
export INSTALLED=$'libfprint-git\nfprintd\nusbutils'

cat >"$scratch/bin/omarchy-hw-fingerprint" <<'STUB'
#!/bin/bash
exit 0
STUB
cat >"$scratch/bin/sudo" <<'STUB'
#!/bin/bash
# Drop elevation and run the privileged helpers against the retargeted tree.
case "$1" in
  tee | sed | pacman | fprintd-enroll) exec "$@" ;;
  *)
    echo "Unexpected privileged call: $*" >>"${CALL_LOG:?}"
    exit 99
    ;;
esac
STUB
# The setup uses GNU sed -i (no backup arg). macOS /usr/bin/sed rejects that,
# so this stub applies the two insert forms the fingerprint setup actually runs.
cat >"$scratch/bin/sed" <<'STUB'
#!/bin/bash
if [[ ${1:-} != -i || $# -ne 3 ]]; then
  exec /usr/bin/sed "$@"
fi
script=$2
file=$3
tmp=$(mktemp)
if [[ $script == 1i\ * ]]; then
  printf '%s\n' "${script#1i }" >"$tmp"
  cat "$file" >>"$tmp"
elif [[ $script == /pam_fprintd*so/i\ * ]]; then
  insert=${script#*/i }
  while IFS= read -r existing || [[ -n $existing ]]; do
    if [[ $existing == *pam_fprintd.so* ]]; then
      printf '%s\n' "$insert"
    fi
    printf '%s\n' "$existing"
  done <"$file" >"$tmp"
else
  echo "unsupported sed script: $script" >&2
  rm -f "$tmp"
  exit 99
fi
mv "$tmp" "$file"
STUB
cat >"$scratch/bin/pacman" <<'STUB'
#!/bin/bash
case "$1" in
  -Q)
    if [[ $2 == "--" ]]; then
      shift 2
    else
      shift
    fi
    grep -qx -- "$1" <<< "${INSTALLED:-}"
    ;;
  -S)
    printf 'pacman %s\n' "$*" >>"${CALL_LOG:?}"
    exit 0
    ;;
  *)
    printf 'pacman %s\n' "$*" >>"${CALL_LOG:?}"
    exit 99
    ;;
esac
STUB
cat >"$scratch/bin/fprintd-enroll" <<'STUB'
#!/bin/bash
echo enroll >>"${CALL_LOG:?}"
exit 0
STUB
cat >"$scratch/bin/fprintd-verify" <<'STUB'
#!/bin/bash
echo verify >>"${CALL_LOG:?}"
exit 0
STUB
chmod +x "$scratch/bin/"*

# Minimal sudo stack so setup_pam_config can insert fprintd + gate.
printf '%s\n' '#%PAM-1.0' 'auth include system-auth' >"$pam_dir/sudo"

assert_gate_before_fprintd() {
  local pam=$1 description=$2
  local gate_line fprintd_line

  [[ -f $pam ]] || fail "$description: lock PAM exists"
  gate_line=$(grep -n 'omarchy-hw-laptop-closed' "$pam" | head -n1 | cut -d: -f1 || true)
  fprintd_line=$(grep -n 'pam_fprintd\.so' "$pam" | head -n1 | cut -d: -f1 || true)
  [[ -n $gate_line && -n $fprintd_line ]] ||
    fail "$description: lock PAM names both the clamshell gate and pam_fprintd" "$(<"$pam")"
  (( gate_line < fprintd_line )) ||
    fail "$description: clamshell gate comes before pam_fprintd" "$(<"$pam")"
}

run_setup() {
  : >"$CALL_LOG"
  "$setup_copy" >"$scratch/output" 2>&1 ||
    fail "fingerprint setup completes enrollment and writes PAM" "$(<"$scratch/output")"
  if grep -q 'Unexpected privileged call' "$CALL_LOG"; then
    fail "fingerprint setup only uses expected privileged helpers" "$(<"$CALL_LOG")"
  fi
}

lock_pam="$pam_dir/omarchy-lock-fingerprint"

run_setup
assert_gate_before_fprintd "$lock_pam" "fresh lock PAM"
pass "fresh setup writes the clamshell gate before pam_fprintd in lock PAM"

# Reproduce #10173: a lock file without the gate (old setup / manual wipe),
# then re-run. The rewrite must restore the gate, not leave it missing.
cat >"$lock_pam" <<'EOF'
#%PAM-1.0
auth       required                    pam_fprintd.so
account    include                     system-local-login
EOF
! grep -q 'omarchy-hw-laptop-closed' "$lock_pam" || fail "precondition: gate-less lock PAM fixture"

run_setup
assert_gate_before_fprintd "$lock_pam" "re-run lock PAM"
pass "re-running setup restores the clamshell gate in lock PAM"
