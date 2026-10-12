module Equivalence exposing (suite)

{-| The kernel decoders must return exactly what the previous Elm decoders
(tests/Wire3Reference.elm) returned, for ANY bytes: the same value, the same
offset after decoding, and a failure wherever the Elm version failed.

elm/bytes does not expose the offset a decoder stops at, so `run` recovers it:
after decoding, `Bytes.Decode.bytes k` succeeds exactly when k bytes remain or
fewer, so the largest such k gives the offset.

-}

import Bytes exposing (Bytes)
import Bytes.Decode as D exposing (Decoder)
import Bytes.Encode as E
import Expect
import Fuzz exposing (Fuzzer)
import Lamdera.Wire3 as Wire3
import Test exposing (Test, describe, fuzz, test)
import Wire3Reference as Reference


type alias Pair a =
    { name : String
    , reference : Decoder a
    , kernel : Decoder a
    }


{-| The value decoded and the offset reached, or Nothing if decoding failed.
-}
run : Decoder a -> Bytes -> Maybe ( a, Int )
run decoder bytes =
    let
        width =
            Bytes.width bytes

        remaining =
            List.range 0 width
                |> List.filter (\k -> D.decode (D.map2 (\_ _ -> ()) decoder (D.bytes k)) bytes /= Nothing)
                |> List.maximum
    in
    case ( D.decode decoder bytes, remaining ) of
        ( Just value, Just k ) ->
            Just ( value, width - k )

        _ ->
            Nothing


sameAsReference : Pair a -> Bytes -> Expect.Expectation
sameAsReference pair bytes =
    run pair.kernel bytes
        |> Expect.equal (run pair.reference bytes)


type alias Record =
    { count : Int, label : String, items : List Int }


{-| Every decoder pair under test, run on the same bytes. Each list holds
pairs of the same type, so that one fuzzer can drive them all.
-}
checkAll : Bytes -> Expect.Expectation
checkAll bytes =
    Expect.all
        (List.concat
            [ List.map (\p -> \b -> sameAsReference p b) ints
            , List.map (\p -> \b -> sameAsReference p b) strings
            , List.map (\p -> \b -> sameAsReference p b) bools
            , List.map (\p -> \b -> sameAsReference p b) intLists
            , List.map (\p -> \b -> sameAsReference p b) stringLists
            , List.map (\p -> \b -> sameAsReference p b) maybes
            , List.map (\p -> \b -> sameAsReference p b) records
            , List.map (\p -> \b -> sameAsReference p b) nested
            ]
        )
        bytes


ints : List (Pair Int)
ints =
    [ Pair "decodeInt64" Reference.decodeInt64 Wire3.decodeInt64 ]


strings : List (Pair String)
strings =
    [ Pair "decodeString" Reference.decodeString Wire3.decodeString ]


bools : List (Pair Bool)
bools =
    [ Pair "decodeBool" Reference.decodeBool Wire3.decodeBool ]


intLists : List (Pair (List Int))
intLists =
    [ Pair "decodeList decodeInt64" (Reference.decodeList Reference.decodeInt64) (Wire3.decodeList Wire3.decodeInt64) ]


stringLists : List (Pair (List String))
stringLists =
    [ Pair "decodeList decodeString" (Reference.decodeList Reference.decodeString) (Wire3.decodeList Wire3.decodeString) ]


maybes : List (Pair (Maybe (List Bool)))
maybes =
    [ Pair "decodeMaybe (decodeList decodeBool)"
        (Reference.decodeMaybe (Reference.decodeList Reference.decodeBool))
        (Wire3.decodeMaybe (Wire3.decodeList Wire3.decodeBool))
    ]


{-| A record decoded the way the compiler generates record decoders:
`succeedDecode` of the constructor, then one `andMapDecode` per field.
-}
records : List (Pair Record)
records =
    [ Pair "andMapDecode (record)"
        (D.succeed Record
            |> Reference.andMapDecode Reference.decodeInt64
            |> Reference.andMapDecode Reference.decodeString
            |> Reference.andMapDecode (Reference.decodeList Reference.decodeInt64)
        )
        (Wire3.succeedDecode Record
            |> Wire3.andMapDecode Wire3.decodeInt64
            |> Wire3.andMapDecode Wire3.decodeString
            |> Wire3.andMapDecode (Wire3.decodeList Wire3.decodeInt64)
        )
    ]


nested : List (Pair (List (Maybe String)))
nested =
    [ Pair "decodeList (decodeMaybe decodeString)"
        (Reference.decodeList (Reference.decodeMaybe Reference.decodeString))
        (Wire3.decodeList (Wire3.decodeMaybe Wire3.decodeString))
    ]


bytesFromList : List Int -> Bytes
bytesFromList ints_ =
    E.encode (E.sequence (List.map E.unsignedInt8 ints_))


toList : Bytes -> List Int
toList bytes =
    D.decode
        (D.loop ( Bytes.width bytes, [] )
            (\( n, acc ) ->
                if n <= 0 then
                    D.succeed (D.Done (List.reverse acc))

                else
                    D.map (\x -> D.Loop ( n - 1, x :: acc )) D.unsignedInt8
            )
        )
        bytes
        |> Maybe.withDefault []


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


{-| Byte sequences written by hand for the edge cases of each decoder.
-}
edgeCases : List ( String, List Int )
edgeCases =
    [ ( "empty input", [] )
    , ( "string of length 0", [ 0 ] )
    , ( "string of negative length", [ 1, 65, 66 ] )
    , ( "string longer than the input", [ 20, 65, 66 ] )
    , ( "string: lone high surrogate", [ 6, 0xED, 0xA0, 0x80 ] )
    , ( "string: lone low surrogate", [ 6, 0xED, 0xB0, 0x80 ] )
    , ( "string: UTF-8 sequence cut by the length", [ 2, 0xC3, 0xA9 ] )
    , ( "string: UTF-8 sequence cut by the length, then more", [ 4, 0x41, 0xE2, 0x82, 0xAC, 0x41 ] )
    , ( "string: 4-byte sequence cut by the end of input", [ 8, 0xF0, 0x9F, 0x98 ] )
    , ( "string: overlong encoding", [ 4, 0xC0, 0xAF ] )
    , ( "string: stray continuation byte", [ 2, 0x80 ] )
    , ( "string: byte 0xFF", [ 2, 0xFF ] )
    , ( "string: BOM", [ 6, 0xEF, 0xBB, 0xBF ] )
    , ( "string of 1 ASCII byte", [ 2, 0x61 ] )
    , ( "string of 31 ASCII bytes", 62 :: List.repeat 31 0x61 )
    , ( "string of 32 ASCII bytes (longest in-place read)", 64 :: List.repeat 32 0x61 )
    , ( "string of 33 ASCII bytes", 66 :: List.repeat 33 0x61 )
    , ( "string of 31 ASCII bytes then a non-ASCII byte", 66 :: List.repeat 31 0x61 ++ [ 0xC3, 0xA9 ] )
    , ( "string of 32 ASCII bytes then a non-ASCII byte", 66 :: List.repeat 32 0x61 ++ [ 0xC3, 0xA9 ] )
    , ( "varint 216 (two bytes)", [ 216, 0 ] )
    , ( "varint 251 (two bytes)", [ 251, 255 ] )
    , ( "varint 252 (three bytes)", [ 252, 255, 255 ] )
    , ( "varint 253 (four bytes)", [ 253, 1, 2, 3 ] )
    , ( "varint 254 (five bytes)", [ 254, 255, 255, 255, 255 ] )
    , ( "varint 254 truncated", [ 254, 1, 2 ] )
    , ( "varint 255: float64 1e15", [ 255, 0, 128, 224, 55, 121, 195, 12, 67 ] )
    , ( "varint 255: float64 -2.5", [ 255, 0, 0, 0, 0, 0, 0, 4, 192 ] )
    , ( "varint 255: NaN", [ 255, 0, 0, 0, 0, 0, 0, 248, 127 ] )
    , ( "varint 255: Infinity", [ 255, 0, 0, 0, 0, 0, 0, 240, 127 ] )
    , ( "varint 255: truncated", [ 255, 0, 0 ] )
    , ( "list of negative length", [ 3, 7, 7 ] )
    , ( "list longer than the input", [ 40, 2, 4 ] )
    , ( "maybe tag 2", [ 2, 0 ] )
    , ( "bool 2", [ 2 ] )
    ]


suite : Test
suite =
    describe "Kernel decoders return exactly what the Elm decoders returned"
        [ describe "Edge cases"
            (List.map (\( name, bytes ) -> test name (\_ -> checkAll (bytesFromList bytes))) edgeCases)
        , fuzz randomBytes "Random bytes" checkAll
        , fuzz validEncoding "Valid encodings" checkAll
        , fuzz mutatedEncoding "Valid encodings with one byte changed, cut or extended" checkAll
        ]
