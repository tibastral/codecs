module Lamdera.Migrations exposing (ModelMigration(..), MsgMigration(..), UnimplementedMigration(..))

{-|

@docs ModelMigration, MsgMigration, UnimplementedMigration

-}


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
