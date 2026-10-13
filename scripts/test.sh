#!/usr/bin/env bash
# Runs the elm-test suite of tests/ against the sources of this repository
# (default: all test files; pass elm-test-rs arguments to narrow or to fuzz more,
# e.g. `scripts/test.sh --fuzz 2000`).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
REPO="${REPO:-$HERE/..}"
prepare_app "$REPO"
cd "$APP"
# A package that cannot be downloaded (github.com answering 504, for instance) is
# reported as a network failure, not as a failure of the tests.
status=0
"$(elm_test_rs)" --compiler "$(command -v lamdera)" "$@" \
  "$(cd "$REPO" && pwd)"/tests/*.elm 2>&1 | tee "$WORK/test.log" || status=$?
if [ "$status" -ne 0 ] && network_problem "$WORK/test.log"; then
  echo "a package could not be downloaded: network failure, the tests were not run; run the script again" >&2
fi
exit "$status"
