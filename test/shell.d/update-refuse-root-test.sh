#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# #13329: sudo omarchy update runs mise/hooks as root and leaves root-owned
# installs under ~/.local/share/mise. The update must refuse EUID 0 before any
# user-phase work, matching omarchy-plymouth-set's root-invocation guard.

if unshare --user --map-root-user true 2>/dev/null; then
  output=$(
    unshare --user --map-root-user \
      env OMARCHY_PATH="$ROOT" OMARCHY_UPDATE_LOGGED=1 \
      /usr/bin/bash -p "$ROOT/bin/omarchy-update" -y 2>&1
  ) || status=$?
  status=${status:-0}
  (( status != 0 )) || fail "omarchy-update refuses to run as root" "$output"
  [[ $output == *"as your user"* && $output == *"not under sudo"* ]] ||
    fail "the root refusal explains how to invoke the update safely" "$output"
else
  grep -A4 -Eq '^if \(\( EUID == 0 \)\); then$' "$ROOT/bin/omarchy-update" ||
    fail "omarchy-update retains its root-invocation guard"
  grep -Fq 'run omarchy-update as your user, not under sudo' "$ROOT/bin/omarchy-update" ||
    fail "omarchy-update root refusal keeps its user-facing message"
fi
pass "omarchy-update refuses to run as root so mise stays user-owned"
