#!/usr/bin/env bash
# Mutation check of the tests: applies, one at a time, deliberate bugs to a
# temporary copy of the kernel (src/Elm/Kernel/LamderaCodecs.js) and prints
# "killed" (the tests fail, as they should) or "survivor" (the tests still pass:
# a hole in the tests). The repository itself is never modified.
#
# Each mutant is run in three ways:
#   elm-test-rs     tests/Equivalence.elm, compiled without --optimize;
#   --optimize      the suites of scripts/test-optimize.sh, compiled with --optimize;
#   no --optimize   the same suites, compiled without it.
# The six first mutants (the behaviour of the decoders) must be killed in all
# three. The seven others break unwrapDecoder: its __PROD branch (one mutant),
# the __PROD branch for one caller at a time (five mutants: bytesDecodeStrict,
# decodeList, decodeMaybe and the two decoders of andMapDecode), and its __DEBUG
# branch (one mutant). A branch only exists in one of the two compilation modes:
# each of these must be killed in the mode that uses it (and is not expected to
# change anything in the other).
#
# Fails (exit 1) if any mutant survives in a mode where it must be killed, and
# (exit 2) if the unmodified kernel does not pass in a mode, since "killed" would
# then mean nothing. A package that cannot be downloaded (the first runs fetch
# them from github.com) is not a failure of the kernel: it is retried up to three
# times and then reported as such, with exit 3.
#
# Usage: scripts/mutants.sh [elm-test-rs arguments, e.g. --fuzz 2000]
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
source "$HERE/lib.sh"
REPO="$(cd "${REPO:-$HERE/..}" && pwd)"
KERNEL=src/Elm/Kernel/LamderaCodecs.js
command -v node >/dev/null || { echo "node not found" >&2; exit 1; }
prepare_app "$REPO"
echo "scratch directory: $WORK"
ELM_TEST_RS="$(elm_test_rs)"
LAMDERA="$(command -v lamdera)"
EXTRA=("$@")

# $1: the repository (or a copy) whose package sources are used, $2: the mode
# (elm-test-rs, optimize or debug), $3: where to write the output.
# Returns 0 if the tests pass.
run_mode() {
  set_package_sources "$1"
  case "$2" in
    elm-test-rs)
      (cd "$APP" && "$ELM_TEST_RS" --compiler "$LAMDERA" ${EXTRA[@]+"${EXTRA[@]}"} "$REPO/tests/Equivalence.elm") >"$3" 2>&1 ;;
    *)
      optimize_mode "$2" >"$3" 2>&1 ;;
  esac
}

MUTANT="$WORK/mutant"
survivors=0
total=0

echo "== the unmodified kernel must pass, in the three ways =="
for m in elm-test-rs optimize debug; do
  attempt=1
  until run_mode "$REPO" "$m" "$WORK/baseline-$m.log"; do
    if network_problem "$WORK/baseline-$m.log"; then
      if [ "$attempt" -lt 3 ]; then
        attempt=$((attempt + 1))
        echo "a package could not be downloaded ($m): attempt $attempt of 3"
        continue
      fi
      tail -30 "$WORK/baseline-$m.log"
      echo "a package could not be downloaded ($m), three times: network failure, the kernel was not tested" >&2
      exit 3
    fi
    tail -30 "$WORK/baseline-$m.log"
    echo "the unmodified kernel fails ($m)" >&2
    exit 2
  done
  echo "passes ($m)"
done

echo "== mutants =="

# $1: name, $2: the modes in which it must be killed (words among elm-test-rs,
# optimize, debug), $3: what the mutation does, $4: a sed -E script that applies it.
mutant() {
  local name="$1" required="$2" what="$3" script="$4" m verdict line="" ok=1
  total=$((total + 1))
  mkdir -p "$MUTANT/src"
  cp -R "$REPO/src/." "$MUTANT/src/"
  sed -E -i.orig "$script" "$MUTANT/$KERNEL"
  if cmp -s "$MUTANT/$KERNEL" "$MUTANT/$KERNEL.orig"; then
    echo "the mutation '$name' does not apply to the kernel: update scripts/mutants.sh" >&2
    exit 2
  fi
  for m in elm-test-rs optimize debug; do
    if run_mode "$MUTANT" "$m" "$WORK/mutant-$total-$m.log"; then
      verdict="survives"
      case " $required " in *" $m "*) ok=0 ;; esac
    else
      if network_problem "$WORK/mutant-$total-$m.log"; then
        echo "a package could not be downloaded while testing '$name' ($m): network failure, not a kill" >&2
        exit 3
      fi
      verdict="killed"
    fi
    line="$line  $m: $verdict"
  done
  if [ "$ok" -eq 1 ]; then
    echo "killed    $name: $what"
  else
    echo "survivor  $name: $what"
    survivors=$((survivors + 1))
  fi
  echo "          (required in: $required;$line)"
}

ALL="elm-test-rs optimize debug"

mutant negative-length-offset "$ALL" \
  "decodeString moves the offset by the length when it is negative (it must not move)" \
  's/return __Utils_Tuple2\(start, ..\);/return __Utils_Tuple2(start - len, "");/'

mutant utf8-not-strict "$ALL" \
  "decodeString replaces invalid UTF-8 by U+FFFD instead of falling back to elm/bytes" \
  's/fatal: true/fatal: false/'

mutant varint-arithmetic "$ALL" \
  "the two-byte varint adds 217 instead of 216" \
  's/getUint8\(offset \+ 1\) \+ 216;/getUint8(offset + 1) + 217;/'

mutant maybe-tag-2 "$ALL" \
  "decodeMaybe accepts any tag from 1 up as Just (tag 2 must fail)" \
  's/if \(tag === 1\)/if (tag >= 1)/'

mutant ascii-32-bytes "$ALL" \
  "the in-place read of short ASCII strings drops the last byte of a 32-byte string" \
  's/for \(var i = start; i < end; i\+\+\)/for (var i = start; i < Math.min(end, start + 31); i++)/'

mutant nan-accepted "$ALL" \
  "a varint 255 holding NaN is accepted (it must fail; only Infinity does)" \
  's/if \(f !== f \|\| f === Infinity/if (f === Infinity/'

mutant unwrap-prod-boxed "optimize" \
  "with --optimize, unwrapDecoder reads decoder.a although the decoder is the function itself (bytesDecodeStrict, decodeList, decodeMaybe, andMapDecode)" \
  's/(_LamderaCodecs_unwrapDecoder__PROD\(decoder\) \{ return) decoder;/\1 decoder.a;/'

# The five mutants below break the __PROD branch for one caller at a time: the
# caller reads `.a` of the decoder itself, which is right without --optimize and
# wrong with it (there the decoder is the function). Each must be killed with
# --optimize, which shows that the tests exercise that caller's __PROD path.
mutant prod-caller-bytesDecodeStrict "optimize" \
  "with --optimize, bytesDecodeStrict reads decoder.a directly" \
  's/A2\(_LamderaCodecs_unwrapDecoder\(decoder\), bytes, 0\)/A2(decoder.a, bytes, 0)/'

mutant prod-caller-decodeList "optimize" \
  "with --optimize, decodeList reads decoder.a of its item decoder directly" \
  '/^var _LamderaCodecs_decodeList = /,/^};/ s/_LamderaCodecs_unwrapDecoder\(decoder\)/decoder.a/'

mutant prod-caller-decodeMaybe "optimize" \
  "with --optimize, decodeMaybe reads decoder.a of its inner decoder directly" \
  '/^var _LamderaCodecs_decodeMaybe = /,/^};/ s/_LamderaCodecs_unwrapDecoder\(decoder\)/decoder.a/'

mutant prod-caller-andMapDecode-argument "optimize" \
  "with --optimize, andMapDecode reads decoder.a of the argument decoder directly" \
  '/^var _LamderaCodecs_andMapDecode = /,/^\}\);/ s/_LamderaCodecs_unwrapDecoder\(decoder\)/decoder.a/'

mutant prod-caller-andMapDecode-function "optimize" \
  "with --optimize, andMapDecode reads functionDecoder.a of the function decoder directly" \
  '/^var _LamderaCodecs_andMapDecode = /,/^\}\);/ s/_LamderaCodecs_unwrapDecoder\(functionDecoder\)/functionDecoder.a/'

mutant unwrap-debug-unboxed "elm-test-rs debug" \
  "without --optimize, unwrapDecoder returns the boxed decoder instead of its function" \
  's/(_LamderaCodecs_unwrapDecoder__DEBUG\(decoder\) \{ return) decoder\.a;/\1 decoder;/'

echo
echo "$((total - survivors)) of $total mutants killed where they must be"
[ "$survivors" -eq 0 ]
