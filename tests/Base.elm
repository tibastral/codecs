module Base exposing (roundtrips, suite)

import Bytes.Encode
import Dict
import Expect
import Fuzz exposing (Fuzzer)
import Lamdera.Wire3 as Wire3
import Set
import Test exposing (Test, describe, fuzz, test)


type alias Codec a =
    { encode : a -> Wire3.Encoder
    , decode : Wire3.Decoder a
    }


succeed : a -> Codec a
succeed result =
    { encode = \_ -> Wire3.encodeUnit ()
    , decode = Wire3.succeedDecode result
    }


suite : Test
suite =
    describe "Testing roundtrips"
        [ describe "Basic" basicTests
        , describe "Containers" containersTests
        , describe "Object" objectTests
        , describe "maybe" maybeTests
        , describe "succeed"
            [ test "roundtrips"
                (\_ ->
                    let
                        codec : Codec number
                        codec =
                            succeed 632
                    in
                    Wire3.bytesDecodeStrict codec.decode (Bytes.Encode.sequence [] |> Bytes.Encode.encode)
                        |> Expect.equal (Just 632)
                )
            ]
        ]


roundtrips : Fuzzer a -> Codec a -> Test
roundtrips fuzzer codec =
    fuzz fuzzer "is a roundtrip" <|
        \value ->
            value
                |> codec.encode
                |> Bytes.Encode.encode
                |> Wire3.bytesDecodeStrict codec.decode
                |> Expect.equal (Just value)


roundtripsWithin : Fuzzer Float -> Codec Float -> Test
roundtripsWithin fuzzer codec =
    fuzz fuzzer "is a roundtrip" <|
        \value ->
            case
                value
                    |> codec.encode
                    |> Bytes.Encode.encode
                    |> Wire3.bytesDecodeStrict codec.decode
            of
                Nothing ->
                    Expect.fail "Decoding failed"

                Just v ->
                    if isNaN value then
                        if isNaN v then
                            Expect.pass

                        else
                            Expect.fail "NaN decoded to non-NaN"

                    else
                        v
                            |> Expect.within (Expect.Relative 0.000001) value


basicTests : List Test
basicTests =
    [ describe "String"
        [ roundtrips Fuzz.string { encode = Wire3.encodeString, decode = Wire3.decodeString }
        ]
    , describe "Int"
        [ roundtrips Fuzz.int { encode = Wire3.encodeInt, decode = Wire3.decodeInt }
        ]
    , describe "Float"
        [ roundtrips
            (Fuzz.oneOf
                [ Fuzz.niceFloat
                , Fuzz.constant (1 / 0)
                , Fuzz.constant (-1 / 0)
                ]
            )
            { encode = Wire3.encodeFloat, decode = Wire3.decodeFloat }
        , describe "Works for NaN"
            [ roundtripsWithin Fuzz.float { encode = Wire3.encodeFloat, decode = Wire3.decodeFloat }
            ]
        ]
    , describe "Bool"
        [ roundtrips Fuzz.bool { encode = Wire3.encodeBool, decode = Wire3.decodeBool }
        ]
    ]


containersTests : List Test
containersTests =
    [ describe "Array"
        [ roundtrips (Fuzz.array Fuzz.int)
            { encode = Wire3.encodeArray Wire3.encodeInt
            , decode = Wire3.decodeArray Wire3.decodeInt
            }
        ]
    , describe "Codec.list"
        [ roundtrips (Fuzz.list Fuzz.int)
            { encode = Wire3.encodeList Wire3.encodeInt
            , decode = Wire3.decodeList Wire3.decodeInt
            }
        ]
    , describe "Codec.dict"
        [ roundtrips
            (Fuzz.map2 Tuple.pair Fuzz.string Fuzz.int
                |> Fuzz.list
                |> Fuzz.map Dict.fromList
            )
            { encode = Wire3.encodeDict Wire3.encodeString Wire3.encodeInt
            , decode = Wire3.decodeDict Wire3.decodeString Wire3.decodeInt
            }
        ]
    , describe "Codec.set"
        [ roundtrips
            (Fuzz.list Fuzz.int |> Fuzz.map Set.fromList)
            { encode = Wire3.encodeSet Wire3.encodeInt
            , decode = Wire3.decodeSet Wire3.decodeInt
            }
        ]
    , describe "Codec.tuple"
        [ roundtrips
            (Fuzz.pair Fuzz.int Fuzz.int)
            { encode = Wire3.encodePair Wire3.encodeInt Wire3.encodeInt
            , decode = Wire3.decodePair Wire3.decodeInt Wire3.decodeInt
            }
        ]
    ]


objectTests : List Test
objectTests =
    [ describe "with 2 fields"
        [ roundtrips
            (Fuzz.map2
                (\a b ->
                    { a = a
                    , b = b
                    }
                )
                Fuzz.int
                Fuzz.int
            )
            { encode =
                \v ->
                    Wire3.encodeSequenceWithoutLength
                        [ Wire3.encodeInt v.a
                        , Wire3.encodeInt v.b
                        ]
            , decode =
                Wire3.succeedDecode
                    (\a b ->
                        { a = a
                        , b = b
                        }
                    )
                    |> Wire3.andMapDecode Wire3.decodeInt
                    |> Wire3.andMapDecode Wire3.decodeInt
            }
        ]
    ]


maybeTests : List Test
maybeTests =
    [ describe "single"
        [ roundtrips
            (Fuzz.oneOf
                [ Fuzz.constant Nothing
                , Fuzz.map Just Fuzz.int
                ]
            )
            { encode = Wire3.encodeMaybe Wire3.encodeInt
            , decode = Wire3.decodeMaybe Wire3.decodeInt
            }
        ]
    , describe "double"
        [ roundtrips
            (Fuzz.oneOf
                [ Fuzz.constant Nothing
                , Fuzz.constant <| Just Nothing
                , Fuzz.map (Just << Just) Fuzz.int
                ]
            )
            { encode = Wire3.encodeMaybe (Wire3.encodeMaybe Wire3.encodeInt)
            , decode = Wire3.decodeMaybe (Wire3.decodeMaybe Wire3.decodeInt)
            }
        ]
    ]
