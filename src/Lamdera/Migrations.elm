module Lamdera.Migrations exposing (decodeType, decodeSequence, intListFromBytes, intListToBytes, CurrentType(..), UpgradeResult(..), Migration(..), UnimplementedMigration(..))

{-|

@docs decodeType, decodeSequence, intListFromBytes, intListToBytes, CurrentType, UpgradeResult, Migration, UnimplementedMigration

-}

import Bytes as B exposing (Bytes)
import Bytes.Decode as D
import Bytes.Encode as E


{-| -}
type CurrentType backendModel frontendModel frontendMsg toBackend backendMsg toFrontend
    = CurrentBackendModel ( backendModel, Cmd backendMsg )
    | CurrentFrontendModel ( frontendModel, Cmd frontendMsg )
    | CurrentFrontendMsg ( frontendMsg, Cmd frontendMsg )
    | CurrentToBackend ( toBackend, Cmd backendMsg )
    | CurrentBackendMsg ( backendMsg, Cmd backendMsg )
    | CurrentToFrontend ( toFrontend, Cmd frontendMsg )


{-| -}
type UpgradeResult backendModel frontendModel frontendMsg toBackend backendMsg toFrontend
    = AlreadyCurrent (CurrentType backendModel frontendModel frontendMsg toBackend backendMsg toFrontend)
    | Upgraded (CurrentType backendModel frontendModel frontendMsg toBackend backendMsg toFrontend)
    | UnknownVersion ( Int, String, List Int )
    | UnknownType String
    | DecoderError


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
decodeType :
    Int -- version
    -> List Int -- intList
    -> D.Decoder oldValue -- decoderOld
    -> Result String ( oldValue, Cmd msg )
decodeType version intList decoderOld =
    case D.decode decoderOld (intListToBytes intList) of
        Just oldValue ->
            let
                x =
                    Debug.log ("[decodeType] decoded old value:" ++ Debug.toString oldValue)
            in
            Ok ( oldValue, Cmd.none )

        Nothing ->
            -- @TODO This would mean data has been manipulated or corrupted,
            -- or we have a bug in our encoder/decoder generation
            let
                err =
                    "[decodeType] impossbile happened; failed to decode in version " ++ String.fromInt version

                x =
                    Debug.log err
            in
            Err err
