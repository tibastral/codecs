module EvergreenTests exposing (intTests)

import Bytes.Decode exposing (decode)
import Bytes.Encode exposing (encode)
import Expect exposing (Expectation)
import Fuzz exposing (..)
import Fuzz.Table exposing (fuzzTable)
import Fuzz.Unique
import Lamdera.Evergreen exposing (..)
import Test exposing (..)


intTests : Test
intTests =
    describe "variable length int encodings"
        [ fuzzTable (oneOf [Fuzz.Unique.int, int])
            "simple int fuzzer"
            (jitter [ 0, 1, 2, 215, 9431, 256 * 256, 256 * 256 * 256, 256 * 256 * 256 * 256 ])
          <|
            \v ->
                encode (encodeInt v)
                    |> decode decodeInt
                    |> Expect.equal (Just v)
        ]


jitter l =
    l
        |> List.concatMap
            (\v ->
                [ v
                , v // 2
                , v * 2
                ]
            )
        |> List.concatMap
            (\v ->
                [ v
                , v - 2
                , v - 1
                , v + 1
                , v + 2
                ]
            )
        |> List.concatMap
            (\v ->
                [ v
                , -v
                ]
            )
