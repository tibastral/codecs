module AvoidNanAndInfInInt exposing (noInfinity, noNaN)

import Expect
import Lamdera.Wire3 as Wire3
import Test exposing (Test)


noNaN : Test
noNaN =
    checkDecodingFailsFor "NaN" (round (0 / 0))


noInfinity : Test
noInfinity =
    checkDecodingFailsFor "Infinity" (round (1 / 0))


checkDecodingFailsFor : String -> Int -> Test
checkDecodingFailsFor label input =
    Test.test ("Decoding must fail if the value is " ++ label) <|
        \_ ->
            let
                encoded : Wire3.Bytes
                encoded =
                    Wire3.encodeInt input
                        |> Wire3.bytesEncode
            in
            Wire3.bytesDecodeStrict Wire3.decodeInt encoded
                |> Expect.equal Nothing
