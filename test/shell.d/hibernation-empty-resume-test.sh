#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

setup="$ROOT/bin/omarchy-hibernation-setup"
[[ -f $setup ]] || fail "hibernation setup is present"

# Must require both device and offset before writing the drop-in.
grep -Eq '\[\[ -z \$RESUME_DEVICE \|\| -z \$RESUME_OFFSET \]\]' "$setup" ||
  fail "setup refuses an empty resume device or offset" "$(grep -n RESUME_ "$setup" | head -20)"

# The old write gate (offset-only) must be gone from the write path.
if grep -n 'if \[\[ -n \$RESUME_OFFSET \]\]' "$setup" | grep -v 'already\|Fixing\|empty resume_offset'; then
  fail "setup must not write resume= on offset alone"
fi

grep -Fq 'resume=[[:space:]]+resume_offset=' "$setup" ||
  fail "setup detects the empty-device drop-in pattern on re-entry"

mig="$ROOT/migrations/1789972000.sh"
[[ -f $mig ]] || fail "migration 1789972000.sh exists"
grep -Fq 'resume=[[:space:]]+resume_offset=' "$mig" ||
  fail "migration removes empty resume= drop-ins"

pass "hibernation setup and migration refuse empty resume= device"
