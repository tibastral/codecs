module Wire3Reference exposing (andMapDecode, decodeBool, decodeInt64, decodeList, decodeMaybe, decodeString)

{-| The Elm implementations of the Wire3 decoders that the kernel now provides,
copied from Lamdera.Wire3 before the change (with its `succeedDecode`,
`failDecode` and `decodeFloat64` aliases inlined). tests/Equivalence.elm checks
that the kernel decoders return exactly what these returned.
-}

import Bytes as B
import Bytes.Decode as D exposing (Decoder)


andMapDecode : Decoder a -> Decoder (a -> b) -> Decoder b
andMapDecode d d2 =
    D.andThen (\v -> D.map v d) d2


intDivBy : Int -> Int -> Int
intDivBy b a =
    let
        v =
            toFloat a / toFloat b
    in
    if v < 0 then
        -(floor -v)

    else
        floor v


unsignedToSigned : Int -> Int
unsignedToSigned i =
    if modBy 2 i == 1 then
        (i + 1) |> intDivBy -2

    else
        i |> intDivBy 2


decodeFloat64 : Decoder Float
decodeFloat64 =
    D.float64 B.LE


decodeInt64 : Decoder Int
decodeInt64 =
    let
        d =
            andMapDecode D.unsignedInt8
    in
    D.unsignedInt8
        |> D.andThen
            (\n0 ->
                if n0 <= 215 then
                    D.succeed n0 |> D.map unsignedToSigned

                else if n0 < 252 then
                    D.succeed (\b0 -> (n0 - 216) * 256 + b0 + 216) |> d |> D.map unsignedToSigned

                else if n0 == 252 then
                    D.succeed (\b0 b1 -> b0 * 256 + b1) |> d |> d |> D.map unsignedToSigned

                else if n0 == 253 then
                    D.succeed (\b0 b1 b2 -> (b0 * 256 + b1) * 256 + b2) |> d |> d |> d |> D.map unsignedToSigned

                else if n0 == 254 then
                    D.succeed (\b0 b1 b2 b3 -> ((b0 * 256 + b1) * 256 + b2) * 256 + b3) |> d |> d |> d |> d |> D.map unsignedToSigned

                else
                    decodeFloat64
                        |> D.andThen
                            (\n1 ->
                                if isNaN n1 || isInfinite n1 then
                                    D.fail

                                else
                                    D.succeed (floor n1)
                            )
            )


decodeString : Decoder String
decodeString =
    decodeInt64
        |> D.andThen D.string


decodeList : Decoder a -> Decoder (List a)
decodeList decoder =
    let
        listStep : ( Int, List a ) -> Decoder (D.Step ( Int, List a ) (List a))
        listStep ( n, xs ) =
            if n <= 0 then
                D.succeed (D.Done xs)

            else
                D.map (\x -> D.Loop ( n - 1, x :: xs )) decoder
    in
    decodeInt64
        |> D.andThen (\len -> D.loop ( len, [] ) listStep |> D.map List.reverse)


decodeBool : Decoder Bool
decodeBool =
    D.unsignedInt8
        |> D.andThen
            (\s ->
                case s of
                    0 ->
                        D.succeed False

                    1 ->
                        D.succeed True

                    _ ->
                        D.fail
            )


decodeMaybe : Decoder a -> Decoder (Maybe a)
decodeMaybe decVal =
    D.unsignedInt8
        |> D.andThen
            (\c ->
                case c of
                    0 ->
                        D.succeed Nothing

                    1 ->
                        decVal |> D.map Just

                    _ ->
                        D.fail
            )
