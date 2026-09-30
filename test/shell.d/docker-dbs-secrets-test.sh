#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
mkdir -p "$stub_bin"

cat >"$stub_bin/sudo" <<'SH'
#!/bin/bash
# Drop the leading sudo and run docker stub directly when requested.
if [[ $1 == docker ]]; then
  shift
  exec docker "$@"
fi
echo "unexpected privileged command" >&2
exit 99
SH
chmod +x "$stub_bin/sudo"

cat >"$stub_bin/docker" <<'SH'
#!/bin/bash
printf 'docker' >>"$OMARCHY_DOCKER_DBS_LOG"
for arg in "$@"; do
  printf '\t%s' "$arg" >>"$OMARCHY_DOCKER_DBS_LOG"
done
printf '\n' >>"$OMARCHY_DOCKER_DBS_LOG"
exit "${DOCKER_EXIT:-0}"
SH
chmod +x "$stub_bin/docker"

cat >"$stub_bin/openssl" <<'SH'
#!/bin/bash
# Deterministic "random" for the test.
if [[ $1 == rand && $2 == -base64 ]]; then
  echo 'TESTSECRET+/BASE64VALUE=='
  exit 0
fi
if [[ $1 == rand && $2 == -hex ]]; then
  echo 'aabbccddeeff001122334455'
  exit 0
fi
exec /usr/bin/openssl "$@"
SH
chmod +x "$stub_bin/openssl"

export HOME="$test_tmp/home"
export XDG_CONFIG_HOME="$HOME/.config"
export PATH="$stub_bin:$PATH"
export OMARCHY_DOCKER_DBS_LOG="$test_tmp/docker.log"
mkdir -p "$HOME"

: >"$OMARCHY_DOCKER_DBS_LOG"
bash "$ROOT/bin/omarchy-install-docker-dbs" PostgreSQL >/dev/null

creds="$XDG_CONFIG_HOME/omarchy/docker-dbs/postgres.env"
[[ -f $creds ]] || fail "postgres credentials file was written"
[[ $(stat -f '%Lp' "$creds" 2>/dev/null || stat -c '%a' "$creds") == *600 ]] ||
  fail "credentials file must be mode 600" "$(ls -l "$creds")"
grep -q 'POSTGRES_PASSWORD=' "$creds" || fail "credentials file carries POSTGRES_PASSWORD"
grep -q 'POSTGRES_HOST_AUTH_METHOD=trust' "$OMARCHY_DOCKER_DBS_LOG" &&
  fail "postgres must not use trust auth" "$(cat "$OMARCHY_DOCKER_DBS_LOG")"
grep -q 'POSTGRES_PASSWORD=' "$OMARCHY_DOCKER_DBS_LOG" ||
  fail "postgres docker run must pass POSTGRES_PASSWORD" "$(cat "$OMARCHY_DOCKER_DBS_LOG")"
pass "PostgreSQL gets a generated password and no trust auth"

: >"$OMARCHY_DOCKER_DBS_LOG"
bash "$ROOT/bin/omarchy-install-docker-dbs" MongoDB >/dev/null
grep -q 'admin123' "$OMARCHY_DOCKER_DBS_LOG" &&
  fail "MongoDB must not use the hardcoded admin123 password" "$(cat "$OMARCHY_DOCKER_DBS_LOG")"
grep -q 'admin123' "$XDG_CONFIG_HOME/omarchy/docker-dbs/mongodb.env" &&
  fail "MongoDB creds file must not contain admin123"
pass "MongoDB no longer uses hardcoded admin123"

# Static guarantee the script itself dropped empty-password / trust flags.
grep -E 'ALLOW_EMPTY|HOST_AUTH_METHOD=trust|admin123|@dmin123' "$ROOT/bin/omarchy-install-docker-dbs" &&
  fail "install-docker-dbs still contains empty/hardcoded credential flags" ||
  pass "install-docker-dbs source has no empty/hardcoded credential flags"

# Failed repeat installs must retain the credential for the existing container.
for database in 'MySQL:mysql' 'PostgreSQL:postgres' 'MariaDB:mariadb' 'Redis:redis' 'MongoDB:mongodb' 'MSSQL:mssql'; do
  db=${database%%:*}
  name=${database#*:}
  creds="$XDG_CONFIG_HOME/omarchy/docker-dbs/$name.env"
  printf 'previous-working-secret\n' >"$creds"
  cp "$creds" "$test_tmp/expected"
  if DOCKER_EXIT=42 bash "$ROOT/bin/omarchy-install-docker-dbs" "$db" >"$test_tmp/failure" 2>&1; then
    fail "$db must report container creation failure"
  fi
  cmp -s "$creds" "$test_tmp/expected" || fail "$db failed repeat install preserves prior credentials"
  candidate=$(find "${creds%/*}" -name ".$name.env.*" -type f | head -1)
  [[ -n $candidate ]] || fail "$db retains private recovery credentials"
  [[ $(stat -f '%Lp' "$candidate" 2>/dev/null || stat -c '%a' "$candidate") == *600 ]] || fail "$db recovery credentials are private"
  grep -Fq "$candidate" "$test_tmp/failure" || fail "$db reports the recovery file"
  pass "$db failed repeat install preserves working credentials"
done

cat >"$stub_bin/mv" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$stub_bin/mv"
creds="$XDG_CONFIG_HOME/omarchy/docker-dbs/postgres.env"
cp "$creds" "$test_tmp/expected"
if bash "$ROOT/bin/omarchy-install-docker-dbs" PostgreSQL >"$test_tmp/publish-failure" 2>&1; then
  fail "credential publication failure must propagate"
fi
cmp -s "$creds" "$test_tmp/expected" || fail "failed credential publication preserves previous file"
grep -q 'candidate credentials retained' "$test_tmp/publish-failure" || fail "failed publication reports recoverable credentials"
pass "failed publication preserves old credentials and retains the new secret"
