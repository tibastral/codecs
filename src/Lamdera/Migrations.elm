module Lamdera.Migrations exposing (decodeSequence, intListFromBytes, intListToBytes, Migration(..), UnimplementedMigration(..), encode)

{-|

@docs decodeSequence, intListFromBytes, intListToBytes, Migration, UnimplementedMigration, encode

-}

import Bytes as B exposing (Bytes)
import Bytes.Decode as D
import Bytes.Encode as E


{-| -}
type Migration a msg
    = Unchanged
    | Migrated ( a, Cmd msg )
    | IgnoredOldValues -- @TODO examples for this?


{-| -}
type UnimplementedMigration
    = Unimplemented


{-| -}
intListFromBytes : Bytes -> List Int
intListFromBytes bytes =
    D.decode (decodeSequence (B.width bytes) D.unsignedInt8) bytes |> Maybe.withDefault [ 47111, 11147, 1, 2, 3, 47111 ]


{-| -}
intListToBytes : List Int -> Bytes
intListToBytes s =
    E.encode (E.sequence (List.map E.unsignedInt8 s))


{-| -}
decodeSequence : Int -> D.Decoder a -> D.Decoder (List a)
decodeSequence len decoder =
    let
        listStep : ( Int, List a ) -> D.Decoder (D.Step ( Int, List a ) (List a))
        listStep ( n, xs ) =
            if n <= 0 then
                D.succeed (D.Done xs)

            else
                D.map (\x -> D.Loop ( n - 1, x :: xs )) decoder
    in
    D.loop ( len, [] ) listStep |> D.map List.reverse


{-| -}
encode : E.Encoder -> B.Bytes
encode =
    E.encode
