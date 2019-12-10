module Lamdera.Migrations exposing (decodeSequence, intListFromBytes, intListToBytes, ModelMigration(..), MsgMigration(..), UnimplementedMigration(..), encode)

{-|

@docs decodeSequence, intListFromBytes, intListToBytes, ModelMigration, MsgMigration, UnimplementedMigration, encode

-}

import Bytes as B exposing (Bytes)
import Bytes.Decode as D
import Bytes.Encode as E


{-| -}
type ModelMigration model msg
    = ModelUnchanged
    | ModelMigrated ( model, Cmd msg )


{-| -}
type MsgMigration msg cmdMsg
    = MsgUnchanged
    | MsgIgnoreOldValues
    | MsgMigrated ( msg, Cmd cmdMsg )


{-| -}
type UnimplementedMigration
    = Unimplemented


{-| -}
intListFromBytes : Bytes -> List Int
intListFromBytes bytes =
    D.decode (decodeSequence (B.width bytes) D.unsignedInt8) bytes |> Maybe.withDefault [ 0, 0, 0, 0, 0 ]


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
