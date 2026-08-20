module Test.Flashcards.ProgressSpec
  ( spec
  )
  where

import Prelude

import Data.Argonaut.Parser (jsonParser)
import Data.DateTime.Instant (Instant, instant)
import Data.Bifunctor (lmap)
import Data.Either (Either(..), isLeft)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromJust)
import Data.Time.Duration (Milliseconds(..))
import Flashcards.Types.Card (Rank(..))
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Progress (CardProgress, Progress)
import Flashcards.Types.Progress as Progress
import Partial.Unsafe (unsafePartial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)

at :: Number -> Instant
at ms = unsafePartial $ fromJust $ instant $ Milliseconds ms

-- | `due` is derived from `seen` so records are distinguishable in assertions.
entry :: Int -> Int -> Int -> Progress -> Progress
entry rank box seen =
  Progress.insert (Rank rank) { box, due: at (Int.toNumber seen * 1000.0), seen, lapses: 0, missed: 0, direction: Recognition }

boxOf :: Int -> Progress -> Maybe Int
boxOf rank p = _.box <$> Progress.lookup (Rank rank) p

seenOf :: Int -> Progress -> Maybe Int
seenOf rank p = _.seen <$> Progress.lookup (Rank rank) p

-- | Parse a literal payload, flattening both failure types to a message.
decode :: String -> Either String Progress.Saved
decode raw = do
  json <- lmap (const "not valid JSON") $ jsonParser raw
  lmap (const "not a valid payload") $ Progress.fromJson json

spec :: Spec Unit
spec = do
  describe "merge" do
    it "takes the record with more sightings behind it" do
      let
        phone = Progress.empty # entry 1 1 2
        laptop = Progress.empty # entry 1 4 9
      boxOf 1 (Progress.merge phone laptop) `shouldEqual` Just 4
      seenOf 1 (Progress.merge phone laptop) `shouldEqual` Just 9

    it "is symmetric when one side is strictly ahead" do
      let
        phone = Progress.empty # entry 1 1 2
        laptop = Progress.empty # entry 1 4 9
      Progress.merge phone laptop `shouldEqual` Progress.merge laptop phone

    it "keeps cards only one side has ever seen" do
      let
        phone = Progress.empty # entry 1 3 5
        laptop = Progress.empty # entry 2 2 4
        merged = Progress.merge phone laptop
      seenOf 1 merged `shouldEqual` Just 5
      seenOf 2 merged `shouldEqual` Just 4
      Progress.seenCount merged `shouldEqual` 2

    it "keeps the left-hand record on a tie, so the result is deterministic" do
      let
        left = Progress.empty # entry 1 5 7
        right = Progress.empty # entry 1 0 7
      boxOf 1 (Progress.merge left right) `shouldEqual` Just 5
      boxOf 1 (Progress.merge right left) `shouldEqual` Just 0

    it "leaves progress untouched when merged with nothing" do
      let mine = Progress.empty # entry 1 3 5 # entry 2 1 1
      Progress.merge mine Progress.empty `shouldEqual` mine
      Progress.merge Progress.empty mine `shouldEqual` mine

  describe "the saved format" do
    it "round-trips through JSON" do
      let mine = Progress.empty # entry 1 3 5 # entry 900 1 1
      (_.progress <$> Progress.fromJson (Progress.toJson "deadbeef" mine))
        `shouldEqual` Right mine

    it "records the deck it was written against" do
      (_.deck <$> Progress.fromJson (Progress.toJson "deadbeef" Progress.empty))
        `shouldEqual` Right (Just "deadbeef")

    it "reads a v3 payload, which predates directions" do
      let
        decoded = decode """{"version":3,"deck":"deadbeef","cards":[{"rank":4,"box":2,"due":1000,"seen":6,"lapses":2,"missed":3}]}"""
        directionOf = map (map _.direction <<< Progress.lookup (Rank 4) <<< _.progress) decoded
      -- Every card started life in recognition, so that is the honest default.
      directionOf `shouldEqual` Right (Just Recognition)

    it "round-trips a production card" do
      let
        producing = Progress.insert (Rank 1)
          { box: 2, due: at 5000.0, seen: 9, lapses: 1, missed: 4, direction: Production }
          Progress.empty
      (_.progress <$> Progress.fromJson (Progress.toJson "deadbeef" producing))
        `shouldEqual` Right producing

    it "reads a v2 payload, which predates the miss count" do
      let
        decoded = decode """{"version":2,"deck":"deadbeef","cards":[{"rank":4,"box":1,"due":1000,"seen":6,"lapses":2}]}"""
        missedOf = map (map _.missed <<< Progress.lookup (Rank 4) <<< _.progress) decoded
      -- Absent history reads as zero rather than being invented.
      missedOf `shouldEqual` Right (Just 0)

    it "reads a v1 payload, which predates the deck fingerprint" do
      let decoded = decode """{"version":1,"cards":[{"rank":7,"box":2,"due":1000,"seen":3,"lapses":1}]}"""
      (_.deck <$> decoded) `shouldEqual` Right Nothing
      (seenOf 7 <<< _.progress <$> decoded) `shouldEqual` Right (Just 3)

    it "refuses a payload written by a newer version" do
      decode """{"version":99,"cards":[]}""" `shouldSatisfy` isLeft
