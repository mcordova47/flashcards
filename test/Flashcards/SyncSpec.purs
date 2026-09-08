module Test.Flashcards.SyncSpec
  ( spec
  )
  where

import Prelude

import Data.Maybe (Maybe(..))
import Flashcards.Sync as Sync
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

key :: String
key = "k7m2p9x4w1n8q3r6t5v0y2z7b4d9f1h3"

spec :: Spec Unit
spec = do
  describe "the pairing link" do
    it "carries the key in the query string" do
      Sync.pairingLink "https://palabras.mcord.dev" key
        `shouldEqual` ("https://palabras.mcord.dev/?pair=" <> key)

    it "round-trips" do
      Sync.keyFromPath ("?pair=" <> key) `shouldEqual` Just key

  describe "reading a key off a link" do
    it "finds it among other parameters" do
      Sync.keyFromPath ("?lang=es&pair=" <> key) `shouldEqual` Just key

    it "tolerates a query string with no leading question mark" do
      Sync.keyFromPath ("pair=" <> key) `shouldEqual` Just key

    it "reads nothing out of an ordinary visit" do
      Sync.keyFromPath "" `shouldEqual` Nothing
      Sync.keyFromPath "?lang=es" `shouldEqual` Nothing

    -- Adopting a malformed key would strand the device on a blob the server
    -- will never accept a write to, and it would do it silently.
    it "refuses a key of the wrong length" do
      Sync.keyFromPath "?pair=abc" `shouldEqual` Nothing
      Sync.keyFromPath ("?pair=" <> key <> "x") `shouldEqual` Nothing

    it "refuses one with characters the server will not take" do
      Sync.keyFromPath "?pair=K7M2P9X4W1N8Q3R6T5V0Y2Z7B4D9F1H3" `shouldEqual` Nothing
      Sync.keyFromPath "?pair=../../etc/passwd/aaaaaaaaaaaaaaaa" `shouldEqual` Nothing
      Sync.keyFromPath "?pair=k7m2p9x4w1n8q3r6t5v0y2z7b4d9f1h-" `shouldEqual` Nothing
