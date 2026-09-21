#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

setup="$ROOT/bin/omarchy-hibernation-setup"
migration=$(ls "$ROOT"/migrations/*empty-resume* 2>/dev/null || true)
[[ -f $setup ]] || fail "hibernation setup is present"

# Must require both device and offset before writing the drop-in.
grep -Eq '\[\[ -z \$RESUME_DEVICE \|\| -z \$RESUME_OFFSET \]\]' "$setup" ||
  fail "setup refuses an empty resume device or offset" "$(grep -n RESUME_ "$setup" | head -20)"

! grep -Eq 'if \[\[ -n \$RESUME_OFFSET \]\]' "$setup" ||
  fail "setup must not write resume= on offset alone"

grep -Eq 'resume=\[\[:space:\]\]\+resume_offset=' "$setup" ||
  fail "setup detects the empty-device drop-in pattern on re-entry"

mig=$(ls "$ROOT"/migrations/1789972000.sh)
[[ -f $mig ]] || fail "migration 1789972000.sh exists"
grep -Eq 'resume=\[\[:space:\]\]\+resume_offset=' "$mig" ||
  fail "migration removes empty resume= drop-ins"

pass "hibernation setup and migration refuse empty resume= device"
