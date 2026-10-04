#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT
mkdir -p "$test_tmp/bin" "$test_tmp/home"

# Decode the actual query with fontconfig itself. Only an exact installed
# family gets returned, so a full dump or an unescaped pattern cannot pass.
cat >"$test_tmp/bin/fc-list" <<'MOCK'
#!/bin/bash
[[ $# == 1 && $1 == :family=* ]] || exit 1
family=$(fc-pattern -f '%{family}' "$1")
[[ $family == "$TEST_FONT_FAMILY" ]] || exit 1
printf '%s\n' "$family"
MOCK
for stub in omarchy-restart-shell omarchy-hook; do
  printf '#!/bin/bash\nexit 0\n' >"$test_tmp/bin/$stub"
done
for stub in pgrep omarchy-cmd-present; do
  printf '#!/bin/bash\nexit 1\n' >"$test_tmp/bin/$stub"
done
chmod +x "$test_tmp/bin"/*

for family in "Test Mono" "Test, Mono" "Test: Mono" "Test, Mono: Style"; do
  HOME="$test_tmp/home" PATH="$test_tmp/bin:$PATH" OMARCHY_PATH="$ROOT" \
    TEST_FONT_FAMILY="$family" "$ROOT/bin/omarchy-font-set" "$family"
  grep -Fq "<string>$family</string>" "$test_tmp/home/.config/fontconfig/fonts.conf" ||
    fail "font-set writes the literal family after its filtered lookup" "$family"
  pass "font-set looks up the exact family: $family"
done

if HOME="$test_tmp/home" PATH="$test_tmp/bin:$PATH" OMARCHY_PATH="$ROOT" \
  TEST_FONT_FAMILY="Test Mono" "$ROOT/bin/omarchy-font-set" "Missing Mono"; then
  fail "font-set rejects a family not returned by its filtered lookup"
fi
pass "font-set rejects an uninstalled family"
