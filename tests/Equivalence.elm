module Equivalence exposing (suite)

{-| The kernel decoders must return exactly what the previous Elm decoders
(tests/Wire3Reference.elm) returned, for ANY bytes: the same value, the same
offset after decoding, and a failure wherever the Elm version failed. The
comparison itself is in tests/Comparison.elm; here it is driven by elm-test,
with hand-written edge cases and fuzzers.

-}

import Bytes exposing (Bytes)
import Bytes.Encode as E
import Comparison exposing (bytesFromList, edgeCases, mismatches, toList)
import Expect
import Fuzz exposing (Fuzzer)
import Lamdera.Wire3 as Wire3
import Test exposing (Test, describe, fuzz, test)


checkAll : Bytes -> Expect.Expectation
checkAll bytes =
    mismatches bytes |> Expect.equal []


randomBytes : Fuzzer Bytes
randomBytes =
    Fuzz.listOfLengthBetween 0 48 (Fuzz.intRange 0 255)
        |> Fuzz.map bytesFromList


{-| Strings the encoder can write, including lone surrogates (which elm/bytes
writes as invalid UTF-8) and characters of every UTF-8 width.
-}
trickyString : Fuzzer String
trickyString =
    Fuzz.oneOf
        [ Fuzz.string
        , Fuzz.asciiString
        , Fuzz.listOfLengthBetween 0 6 (Fuzz.oneOfValues [ 0x41, 0xE9, 0x20AC, 0xD800, 0xDBFF, 0xDC00, 0xDFFF, 0x0001F600, 0xFEFF, 0 ])
            |> Fuzz.map (List.map Char.fromCode >> String.fromList)
        ]


{-| Well-formed encodings of each type under test, so that the fuzzer also
reaches the successful paths, which random bytes rarely do.
-}
validEncoding : Fuzzer Bytes
validEncoding =
    Fuzz.oneOf
        [ Fuzz.int |> Fuzz.map Wire3.encodeInt64
        , Fuzz.oneOfValues [ 0, -1, 107, -108, 108, 4000, -4000, 32767, 65536, 2147483647, -2147483648, 4294967296, 9007199254740991 ] |> Fuzz.map Wire3.encodeInt64
        , trickyString |> Fuzz.map Wire3.encodeString
        , Fuzz.bool |> Fuzz.map Wire3.encodeBool
        , Fuzz.listOfLengthBetween 0 5 Fuzz.int |> Fuzz.map (Wire3.encodeList Wire3.encodeInt64)
        , Fuzz.listOfLengthBetween 0 4 trickyString |> Fuzz.map (Wire3.encodeList Wire3.encodeString)
        , Fuzz.maybe (Fuzz.listOfLengthBetween 0 4 Fuzz.bool) |> Fuzz.map (Wire3.encodeMaybe (Wire3.encodeList Wire3.encodeBool))
        , Fuzz.listOfLengthBetween 0 4 (Fuzz.maybe trickyString) |> Fuzz.map (Wire3.encodeList (Wire3.encodeMaybe Wire3.encodeString))
        , Fuzz.map3 (\c l i -> E.sequence [ Wire3.encodeInt64 c, Wire3.encodeString l, Wire3.encodeList Wire3.encodeInt64 i ])
            Fuzz.int
            trickyString
            (Fuzz.listOfLengthBetween 0 4 Fuzz.int)
        ]
        |> Fuzz.map E.encode


{-| A valid encoding with one byte overwritten, then cut or extended: inputs
that start well-formed and go wrong somewhere, where implementations diverge
most easily.
-}
mutatedEncoding : Fuzzer Bytes
mutatedEncoding =
    Fuzz.map4
        (\bytes position value cut ->
            let
                list =
                    toList bytes

                n =
                    List.length list

                mutated =
                    if n == 0 then
                        [ value ]

                    else
                        List.indexedMap
                            (\i x ->
                                if i == modBy n position then
                                    value

                                else
                                    x
                            )
                            list
            in
            bytesFromList
                (if cut >= 0 then
                    List.take (List.length mutated - cut) mutated

                 else
                    mutated ++ List.repeat (negate cut) value
                )
        )
        validEncoding
        (Fuzz.intRange 0 1000)
        (Fuzz.intRange 0 255)
        (Fuzz.intRange -2 2)


suite : Test
suite =
    describe "Kernel decoders return exactly what the Elm decoders returned"
        [ describe "Edge cases"
            (List.map (\( name, bytes ) -> test name (\_ -> checkAll (bytesFromList bytes))) edgeCases)
        , fuzz randomBytes "Random bytes" checkAll
        , fuzz validEncoding "Valid encodings" checkAll
        , fuzz mutatedEncoding "Valid encodings with one byte changed, cut or extended" checkAll
        ]
