# Shared by the scripts of this directory (sourced, not run).
#
# The package has a JavaScript kernel (src/Elm/Kernel/LamderaCodecs.js), so it
# does not compile from its own source directories. Instead, a scratch
# application depends on lamdera/codecs 1.0.0 in a dedicated, initially empty
# ELM_HOME; the package's sources are then overwritten there with the ones of the
# repository under test, and its compiled cache (artifacts.*) is set aside.
#
# Requires: lamdera on the PATH (it downloads the packages: network access),
# node for scripts/test-optimize.sh and scripts/mutants.sh, elm-test-rs for
# scripts/test.sh and scripts/mutants.sh (see README.md).

set -euo pipefail

# $1: the repository (or a copy of it) whose src/ and tests/ are used.
# Sets WORK, ELM_HOME and APP; leaves an application in $APP, whose elm.json
# lets the sources in $1/tests (and $1/tests/Optimize) be compiled against the
# package.
prepare_app() {
  local repo
  repo="$(cd "$1" && pwd)"
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/lamdera-codecs.XXXXXX")"
  export ELM_HOME="$WORK/elm-home"
  APP="$WORK/app"
  mkdir -p "$APP/src" "$WORK/set-aside"
  cat > "$APP/elm.json" <<JSON
{
    "type": "application",
    "source-directories": [ "src", "$repo/tests" ],
    "elm-version": "0.19.1",
    "dependencies": {
        "direct": {
            "elm/bytes": "1.0.8",
            "elm/core": "1.0.5",
            "elm/json": "1.1.3",
            "elm/random": "1.0.0",
            "elm-explorations/test": "2.2.0",
            "lamdera/codecs": "1.0.0"
        },
        "indirect": {
            "elm/html": "1.0.0",
            "elm/time": "1.0.0",
            "elm/virtual-dom": "1.0.3"
        }
    },
    "test-dependencies": { "direct": {}, "indirect": {} }
}
JSON
  cat > "$APP/src/Bootstrap.elm" <<'ELM'
module Bootstrap exposing (main)

import Lamdera.Wire3


main : Program () () ()
main =
    Platform.worker { init = \_ -> ( (), Cmd.none ), update = \_ m -> ( m, Cmd.none ), subscriptions = \_ -> Sub.none }
ELM
  # First compilation: lamdera downloads the packages into the empty ELM_HOME.
  (cd "$APP" && lamdera make src/Bootstrap.elm --output=/dev/null >/dev/null 2>&1) \
    || { echo "could not download the packages with lamdera (network?)" >&2; return 1; }
  set_package_sources "$repo"
}

# $1: a repository (or a copy) whose src/ replaces the package's.
set_package_sources() {
  local package="$ELM_HOME/0.19.1/packages/lamdera/codecs/1.0.0"
  local f aside
  aside="$(mktemp -d "$WORK/set-aside/XXXXXX")"
  for f in "$package"/artifacts*; do
    [ -e "$f" ] && mv "$f" "$aside/"
  done
  mv "$package/src" "$aside/src"
  # The compiled application of the first compilation was built against the downloaded sources.
  [ -e "$APP/elm-stuff" ] && mv "$APP/elm-stuff" "$aside/elm-stuff"
  mkdir -p "$package/src"
  cp -R "$1/src/." "$package/src/"
}

# $1: a log. Succeeds if it holds one of the compiler's messages about a package
# that could not be downloaded (for instance "504 Gateway Time-out" from
# github.com): an incident of the network, which says nothing about the kernel.
network_problem() {
  grep -qE -- '^-- (PROBLEM DOWNLOADING PACKAGE|HTTP PROBLEM|PROBLEM LOADING PACKAGE LIST)' "$1"
}

# The elm-test-rs to use: the one installed by `npm install`, else the one on the PATH.
elm_test_rs() {
  local root
  root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [ -x "$root/node_modules/.bin/elm-test-rs" ]; then
    echo "$root/node_modules/.bin/elm-test-rs"
  else
    command -v elm-test-rs || { echo "elm-test-rs not found: run npm install" >&2; return 1; }
  fi
}

# The number of tests tests/Optimize/Main.elm must run: exactly this many, so
# that a test added or removed is noticed instead of silently changing what is
# checked. Update it with the figure elm-test-rs prints for scripts/test.sh.
EXPECTED_TESTS="${EXPECTED_TESTS:-53}"

# Writes $WORK/run.js: loads the compiled tests/Optimize/Main.elm, waits for its
# report, and exits 1 on failures, 2 if no report arrives, 3 if the number of
# tests run is not $EXPECTED_TESTS. (Whatever its code, the scripts that call it
# only see "failed" and exit 1; the lines it prints say which.)
write_runner() {
  cat > "$WORK/run.js" <<'JS'
const { Elm } = require(process.argv[2]);
const expected = Number(process.argv[3]);
const app = Elm.Optimize.Main.init();
let reported = false;

if (!app.ports || !app.ports.report) {
  console.log("  the program has no report port");
  process.exit(2);
}

app.ports.report.subscribe((r) => {
  reported = true;
  console.log(`ran ${r.ran} tests, ${r.failures} failures`);
  r.first.forEach((d) => console.log(`  failure: ${d}`));
  if (r.failures !== 0) process.exitCode = 1;
  else if (r.ran !== expected) {
    console.log(`  ${expected} tests expected: update EXPECTED_TESTS in scripts/lib.sh if tests were added or removed`);
    process.exitCode = 3;
  }
});

process.on('exit', () => {
  if (!reported) {
    console.log('  the program reported nothing');
    process.exitCode = 2;
  }
});
JS
}

# $1: "optimize" or "debug". Compiles tests/Optimize/Main.elm of $REPO against
# the package sources currently in place, with or without --optimize, runs it in
# node, and prints what it reports. Returns 0 only if all the tests pass.
optimize_mode() {
  local mode="$1" flag="" out
  [ "$mode" = optimize ] && flag="--optimize"
  out="$WORK/main-$mode.js"
  [ -e "$WORK/run.js" ] || write_runner
  (cd "$APP" && lamdera make "$REPO/tests/Optimize/Main.elm" $flag --output="$out" >"$WORK/make.log" 2>&1) \
    || { cat "$WORK/make.log"; echo "compilation failed ($mode)"; return 1; }
  node "$WORK/run.js" "$out" "$EXPECTED_TESTS"
}
