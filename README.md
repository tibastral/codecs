# lamdera/codecs

Lamdera's core codecs (`Lamdera.Wire`, `Lamdera.Wire2`, `Lamdera.Wire3`,
`Lamdera.Migrations`).

## Running the checks

The package has a JavaScript kernel (`src/Elm/Kernel/LamderaCodecs.js`), so it
does not compile from its own source directories. The scripts below put the
sources of this repository in place of `lamdera/codecs 1.0.0` in a fresh
`ELM_HOME` (in a scratch directory under `$TMPDIR`, printed by each script),
inside a scratch application that depends on it. They never modify the
repository. Nothing is assumed of the machine except what follows, and the
first run downloads the packages.

Needed: `lamdera` (0.19.1) on the `PATH` and network access; `node` for
`scripts/test-optimize.sh` and `scripts/mutants.sh`; `elm-test-rs`, found in
`node_modules/.bin` after `npm install`, or else on the `PATH`.

| Command | What it checks |
| --- | --- |
| `scripts/test.sh` | The elm-test suite of `tests/` (add elm-test-rs arguments, such as `--fuzz 2000`). |
| `scripts/test-optimize.sh` | The suites `tests/Equivalence.elm`, `tests/Base.elm` and `tests/AvoidNanAndInfInInt.elm` again, compiled with `--optimize` and without, so that both `_LamderaCodecs_unwrapDecoder__PROD` and `__DEBUG` are exercised (`bytesDecodeStrict` included, through `tests/Base.elm`). elm-test-rs has no `--optimize` option, so `tests/Optimize/Main.elm`, a small program, builds the suites with `Test.Runner.fromTest`, runs them, and reports through a port; the script runs it in node. Exits 1 if a test fails, if the program reports nothing, or if it ran a number of tests other than `EXPECTED_TESTS` (53, set in `scripts/lib.sh`: update it when tests are added or removed). Two lines `❌ bytesDecodeStrict unexpected error: 0` appear in each mode: they are the kernel's log for the NaN and Infinity tests, which hand it a value it must reject. |
| `scripts/mutants.sh` | Applies thirteen deliberate bugs, one at a time, to a temporary copy of the kernel, and runs the tests on each in three ways: `tests/Equivalence.elm` under elm-test-rs, then the suites of `scripts/test-optimize.sh` with `--optimize` and without. Six mutants change the behaviour of the decoders and must be killed in all three; seven break `unwrapDecoder` (`__PROD`, `__DEBUG`, and `__PROD` for each of its four callers one at a time, `andMapDecode` counting for two) and must be killed in the mode that uses that branch. Prints `killed` or `survivor` for each, with the result of each way, and exits 1 if one survives where it must be killed. A package that cannot be downloaded (github.com answering 504, for instance) is retried, then reported as a network failure with exit 3 rather than as a failure of the kernel. |

`tests/Comparison.elm` holds what `tests/Equivalence.elm` compares: the pairs of
decoders (kernel and previous Elm version), the edge cases, and the way the
position a decoder stops at is measured.
