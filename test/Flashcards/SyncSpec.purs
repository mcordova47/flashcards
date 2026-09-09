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
      Sync.keyFromLink ("?pair=" <> key) `shouldEqual` Just key

  describe "reading a key off a link" do
    -- A pasted link arrives whole, from a phone's share sheet or a message.
    it "finds it in a link pasted entire" do
      Sync.keyFromLink ("https://palabras.mcord.dev/?pair=" <> key) `shouldEqual` Just key
      Sync.keyFromLink ("https://palabras.mcord.dev/es?pair=" <> key <> "&lang=es")
        `shouldEqual` Just key

    it "accepts the bare key, for anyone who trimmed it themselves" do
      Sync.keyFromLink key `shouldEqual` Just key

    it "and forgives whitespace, which a paste usually brings" do
      Sync.keyFromLink ("  " <> key <> "\n") `shouldEqual` Just key
      Sync.keyFromLink ("  https://palabras.mcord.dev/?pair=" <> key <> " ") `shouldEqual` Just key

    it "reads nothing out of something that is not one" do
      Sync.keyFromLink "https://example.com" `shouldEqual` Nothing
      Sync.keyFromLink "hello" `shouldEqual` Nothing

    it "finds it among other parameters" do
      Sync.keyFromLink ("?lang=es&pair=" <> key) `shouldEqual` Just key

    it "tolerates a query string with no leading question mark" do
      Sync.keyFromLink ("pair=" <> key) `shouldEqual` Just key

    it "reads nothing out of an ordinary visit" do
      Sync.keyFromLink "" `shouldEqual` Nothing
      Sync.keyFromLink "?lang=es" `shouldEqual` Nothing

    -- Adopting a malformed key would strand the device on a blob the server
    -- will never accept a write to, and it would do it silently.
    it "refuses a key of the wrong length" do
      Sync.keyFromLink "?pair=abc" `shouldEqual` Nothing
      Sync.keyFromLink ("?pair=" <> key <> "x") `shouldEqual` Nothing

    it "refuses one with characters the server will not take" do
      Sync.keyFromLink "?pair=K7M2P9X4W1N8Q3R6T5V0Y2Z7B4D9F1H3" `shouldEqual` Nothing
      Sync.keyFromLink "?pair=../../etc/passwd/aaaaaaaaaaaaaaaa" `shouldEqual` Nothing
      Sync.keyFromLink "?pair=k7m2p9x4w1n8q3r6t5v0y2z7b4d9f1h-" `shouldEqual` Nothing
