module Comparison exposing (bytesFromList, edgeCases, mismatches, toList)

{-| What the kernel decoders and the previous Elm decoders (tests/Wire3Reference.elm)
are compared on. Used by tests/Equivalence.elm, which runs both under elm-test-rs
(without `--optimize`) and, through tests/Optimize/Main.elm, compiled with
`--optimize`.

The kernel decoders must return exactly what the previous Elm decoders returned,
for ANY bytes: the same value, the same offset after decoding, and a failure
wherever the Elm version failed.

elm/bytes does not expose the offset a decoder stops at, so `run` recovers it:
after decoding, `Bytes.Decode.bytes k` succeeds exactly when k bytes remain or
fewer, so the largest such k gives the offset.

-}

import Bytes exposing (Bytes)
import Bytes.Decode as D exposing (Decoder)
import Bytes.Encode as E
import Lamdera.Wire3 as Wire3
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


differs : Pair a -> Bytes -> Maybe String
differs pair bytes =
    if run pair.kernel bytes == run pair.reference bytes then
        Nothing

    else
        Just pair.name


type alias Record =
    { count : Int, label : String, items : List Int }


{-| The names of the decoder pairs that disagree on these bytes: empty if the
kernel and the Elm decoders agree on every pair. Each list below holds pairs of
the same type.
-}
mismatches : Bytes -> List String
mismatches bytes =
    List.concat
        [ List.filterMap (\p -> differs p bytes) ints
        , List.filterMap (\p -> differs p bytes) strings
        , List.filterMap (\p -> differs p bytes) bools
        , List.filterMap (\p -> differs p bytes) intLists
        , List.filterMap (\p -> differs p bytes) stringLists
        , List.filterMap (\p -> differs p bytes) maybes
        , List.filterMap (\p -> differs p bytes) records
        , List.filterMap (\p -> differs p bytes) nested
        ]


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
