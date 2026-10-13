#!/usr/bin/env bash
# Runs the elm-test suites of tests/ (Equivalence, Base, AvoidNanAndInfInInt) in
# the two forms the kernel is compiled in:
#   - with --optimize, where single-constructor types are unboxed and
#     _LamderaCodecs_unwrapDecoder__PROD is used;
#   - without it, where _LamderaCodecs_unwrapDecoder__DEBUG is used.
# elm-test-rs has no --optimize option, so the suites are run by a small program,
# tests/Optimize/Main.elm, which builds them with Test.Runner.fromTest, runs them
# and reports through a port; this script compiles it in each form and runs it in
# node.
# Exits 1 if a test fails, if the program reports nothing (a port never called
# would otherwise look like a success), or if it ran a number of tests other than
# EXPECTED_TESTS (see scripts/lib.sh; a suite silently emptied would otherwise
# look like a success). The exit code is 1 in every case of failure; the lines
# printed say which.
#
# Usage: scripts/test-optimize.sh        (the repository is the one of this script)
#        REPO=<other copy> scripts/test-optimize.sh
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
REPO="$(cd "${REPO:-$HERE/..}" && pwd)"
command -v node >/dev/null || { echo "node not found" >&2; exit 1; }
prepare_app "$REPO"
echo "scratch directory: $WORK"

# Both modes always run, so that a failure of one does not hide the other.
# bytesDecodeStrict logs the two lines "❌ bytesDecodeStrict unexpected error: 0"
# in each mode: they come from the NaN and Infinity tests of
# tests/AvoidNanAndInfInInt.elm, which hand it a value it must reject.
status=0
for mode in optimize debug; do
  echo "== $([ "$mode" = optimize ] && echo "compiled with --optimize" || echo "compiled without --optimize") =="
  if optimize_mode "$mode"; then
    echo "   OK"
  else
    echo "   FAILED"
    status=1
  fi
done
exit $status
