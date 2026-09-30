#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

install_script="$ROOT/install/config/increase-lockout-limit.sh"
migration="$ROOT/migrations/1790385000.sh"

[[ -f $install_script ]] || fail "lockout install script is present"
[[ -f $migration ]] || fail "lockout visibility migration is present"

# The install script must write a preauth line that can report lockout.
grep -Eq 'preauth deny=10 unlock_time=120' "$install_script" ||
  fail "install script sets preauth deny/unlock_time without silent" "$(grep preauth "$install_script" || true)"
! grep -Eq 'preauth[[:space:]]+silent' "$install_script" ||
  fail "install script must not keep preauth silent" "$(grep preauth "$install_script" || true)"
pass "install script drops silent from pam_faillock preauth"

sudoers="$ROOT/etc/sudoers.d/omarchy-passwd-tries"
[[ -f $sudoers ]] || fail "passwd_tries sudoers drop-in is present"
grep -Eq '^Defaults[[:space:]]+!pam_silent[[:space:]]*$' "$sudoers" ||
  fail "sudoers clears pam_silent so faillock messages reach the terminal" "$(cat "$sudoers")"
pass "sudoers allows pam_faillock messages through sudo"


tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

pam="$tmpdir/system-auth"
# Shape of an Arch/Omarchy system-auth preauth line before this fix.
cat >"$pam" <<'EOF'
auth      required                    pam_faillock.so preauth silent deny=10 unlock_time=120
auth      [success=1 default=bad]     pam_unix.so try_first_pass nullok
auth      [default=die]               pam_faillock.so authfail deny=10 unlock_time=120
auth      sufficient                  pam_faillock.so authsucc
EOF

# Run the actual migration, relocating its sole PAM target into this fixture.
# The sudo stub accepts only sed against that synthetic file; it never elevates.
mkdir -p "$tmpdir/bin"
cat >"$tmpdir/bin/sudo" <<'STUB'
#!/bin/bash
[[ $1 == "sed" && ${*: -1} == "$TEST_PAM" ]] || exit 99
shift
exec sed "$@"
STUB
chmod +x "$tmpdir/bin/sudo"
export TEST_PAM="$pam"
sed "s|/etc/pam.d/system-auth|$pam|g" "$migration" >"$tmpdir/migration.sh"
PATH="$tmpdir/bin:$PATH" bash -euo pipefail "$tmpdir/migration.sh"

grep -Eq 'pam_faillock\.so preauth deny=10 unlock_time=120' "$pam" ||
  fail "migration strips silent and keeps deny/unlock_time" "$(grep faillock "$pam")"
! grep -Eq 'preauth[[:space:]]+silent' "$pam" ||
  fail "migration leaves no silent on preauth" "$(grep faillock "$pam")"
grep -Eq 'authfail deny=10 unlock_time=120' "$pam" ||
  fail "migration leaves authfail args alone" "$(grep faillock "$pam")"
pass "migration strips silent from an existing preauth line"

# Idempotent on an already-fixed line.
PATH="$tmpdir/bin:$PATH" bash -euo pipefail "$tmpdir/migration.sh"
grep -c 'pam_faillock\.so' "$pam" | grep -qx 3 ||
  fail "re-running the strip does not duplicate faillock lines" "$(grep faillock "$pam")"
pass "stripping silent is idempotent"

# The migration file itself targets system-auth with the same transform.
grep -Fq '/etc/pam.d/system-auth' "$migration" ||
  fail "migration edits system-auth"
grep -Fq 'preauth' "$migration" && grep -Fq 'silent' "$migration" ||
  fail "migration mentions the silent preauth token"
pass "migration targets the silent preauth on system-auth"

# The upgrade can run after the migration. Exercise its actual system-auth
# transforms against the repaired fixture so it cannot reintroduce silent.
grep -F 'as_root sed -i' "$ROOT/bin/omarchy-upgrade-to-quattro" |
  grep -F '/etc/pam.d/system-auth' >"$tmpdir/upgrade.sh"
[[ -s $tmpdir/upgrade.sh ]] || fail "upgrade system-auth transforms were found"
sed -i "s|/etc/pam.d/system-auth|$pam|g; s/as_root sed/sudo sed/g" "$tmpdir/upgrade.sh"
PATH="$tmpdir/bin:$PATH" bash -euo pipefail "$tmpdir/upgrade.sh"
grep -Eq 'pam_faillock\.so preauth deny=10 unlock_time=120' "$pam" ||
  fail "upgrade preserves visible system-auth lockout" "$(cat "$pam")"
! grep -Eq 'preauth[[:space:]]+silent' "$pam" ||
  fail "upgrade must not restore silent after migration" "$(cat "$pam")"
pass "upgrade preserves the migration's lockout visibility"
