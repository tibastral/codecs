port module Optimize.Main exposing (main)

{-| The elm-test suites of tests/ (Equivalence, Base, AvoidNanAndInfInInt) run
as an ordinary program, so that they can be compiled with `--optimize`:
elm-test-rs has no `--optimize` option, and the kernel has a separate branch for
that mode (`_LamderaCodecs_unwrapDecoder__PROD`).

The program builds the suites with `Test.Runner.fromTest`, runs every test, and
reports through a port how many tests ran and which failed, with the failure
message. A test that is skipped or filtered out (`Test.skip`, `Test.only`) or
invalid counts as a failure, so nothing can silently go unchecked.

scripts/test-optimize.sh compiles this file with and without `--optimize`, runs
it in node, and fails unless the report arrives and covers enough tests.

-}

import AvoidNanAndInfInInt
import Base
import Equivalence
import Expect
import Process
import Random
import Task
import Test exposing (Test, describe)
import Test.Runner as Runner


port report : { ran : Int, failures : Int, first : List String } -> Cmd msg


type Msg
    = Run


main : Program () () Msg
main =
    Platform.worker
        { init = \_ -> ( (), Task.perform (\_ -> Run) (Process.sleep 0) )
        , update = \_ model -> ( model, report summary )
        , subscriptions = \_ -> Sub.none
        }


suite : Test
suite =
    describe "lamdera/codecs"
        [ Equivalence.suite
        , Base.suite
        , AvoidNanAndInfInInt.noNaN
        , AvoidNanAndInfInInt.noInfinity
        ]


{-| The number of random values tried by each fuzz test.
-}
fuzzRuns : Int
fuzzRuns =
    2000


summary : { ran : Int, failures : Int, first : List String }
summary =
    case Runner.fromTest fuzzRuns (Random.initialSeed 20260512) suite of
        Runner.Plain runners ->
            let
                failures =
                    List.concatMap
                        (\runner ->
                            runner.run ()
                                |> List.filterMap Runner.getFailureReason
                                |> List.map
                                    (\reason ->
                                        String.join " > " runner.labels
                                            ++ ": "
                                            ++ reason.description
                                            ++ " given: "
                                            ++ Maybe.withDefault "" reason.given
                                    )
                        )
                        runners
            in
            { ran = List.length runners, failures = List.length failures, first = List.take 10 failures }

        Runner.Only _ ->
            { ran = 0, failures = 1, first = [ "the suite contains Test.only" ] }

        Runner.Skipping _ ->
            { ran = 0, failures = 1, first = [ "the suite contains Test.skip" ] }

        Runner.Invalid message ->
            { ran = 0, failures = 1, first = [ "invalid suite: " ++ message ] }
