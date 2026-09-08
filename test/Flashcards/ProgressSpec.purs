module Test.Flashcards.ProgressSpec
  ( spec
  )
  where

import Prelude

import Data.Argonaut.Core (stringify)
import Data.Argonaut.Parser (jsonParser)
import Data.DateTime.Instant (Instant, instant)
import Data.Bifunctor (lmap)
import Data.Either (Either(..), isLeft)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromJust)
import Data.String as String
import Data.Time.Duration (Milliseconds(..))
import Data.Traversable (traverse)
import Data.Tuple.Nested ((/\))
import Flashcards.Types.Card (Rank(..), Slug(..))
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress
import Partial.Unsafe (unsafePartial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)

at :: Number -> Instant
at ms = unsafePartial $ fromJust $ instant $ Milliseconds ms

-- | `due` is derived from `seen` so records are distinguishable in assertions.
entry :: String -> Int -> Int -> Progress -> Progress
entry slug box seen =
  Progress.insert (Slug slug) { box, due: at (Int.toNumber seen * 1000.0), seen, lapses: 0, missed: 0, direction: Recognition }

boxOf :: String -> Progress -> Maybe Int
boxOf slug p = _.box <$> Progress.lookup (Slug slug) p

seenOf :: String -> Progress -> Maybe Int
seenOf slug p = _.seen <$> Progress.lookup (Slug slug) p

-- | Parse a literal payload, flattening both failure types to a message.
decode :: String -> Either String Progress.Saved
decode raw = do
  json <- lmap (const "not valid JSON") $ jsonParser raw
  lmap (const "not a valid payload") $ Progress.fromJson json

-- | Reassemble a payload whose entries all carry their own slug, which is the
-- | whole of the work for anything written by v5. `Flashcards.Deck.adopt` is
-- | the general case, and needs a deck precisely because older payloads do not
-- | carry one.
resolved :: Progress.Saved -> Maybe Progress
resolved saved = Progress.fromEntries <$> traverse pair saved.cards
  where
    pair c = (_ /\ c.progress) <$> c.slug

spec :: Spec Unit
spec = do
  describe "merge" do
    it "takes the record with more sightings behind it" do
      let
        phone = Progress.empty # entry "yo" 1 2
        laptop = Progress.empty # entry "yo" 4 9
      boxOf "yo" (Progress.merge phone laptop) `shouldEqual` Just 4
      seenOf "yo" (Progress.merge phone laptop) `shouldEqual` Just 9

    it "is symmetric when one side is strictly ahead" do
      let
        phone = Progress.empty # entry "yo" 1 2
        laptop = Progress.empty # entry "yo" 4 9
      Progress.merge phone laptop `shouldEqual` Progress.merge laptop phone

    it "keeps cards only one side has ever seen" do
      let
        phone = Progress.empty # entry "yo" 3 5
        laptop = Progress.empty # entry "no" 2 4
        merged = Progress.merge phone laptop
      seenOf "yo" merged `shouldEqual` Just 5
      seenOf "no" merged `shouldEqual` Just 4
      Progress.seenCount merged `shouldEqual` 2

    it "keeps the left-hand record on a tie, so the result is deterministic" do
      let
        left = Progress.empty # entry "yo" 5 7
        right = Progress.empty # entry "yo" 0 7
      boxOf "yo" (Progress.merge left right) `shouldEqual` Just 5
      boxOf "yo" (Progress.merge right left) `shouldEqual` Just 0

    it "leaves progress untouched when merged with nothing" do
      let mine = Progress.empty # entry "yo" 3 5 # entry "no" 1 1
      Progress.merge mine Progress.empty `shouldEqual` mine
      Progress.merge Progress.empty mine `shouldEqual` mine

  describe "the saved format" do
    it "round-trips through JSON" do
      let mine = Progress.empty # entry "yo" 3 5 # entry "concreto" 1 1
      (resolved <$> Progress.fromJson (Progress.toJson "es" "deadbeef" mine))
        `shouldEqual` Right (Just mine)

    it "records the deck it was written against" do
      (_.deck <$> Progress.fromJson (Progress.toJson "es" "deadbeef" Progress.empty))
        `shouldEqual` Right (Just "deadbeef")

    it "round-trips a production card" do
      let
        producing = Progress.insert (Slug "yo")
          { box: 2, due: at 5000.0, seen: 9, lapses: 1, missed: 4, direction: Production }
          Progress.empty
      (resolved <$> Progress.fromJson (Progress.toJson "es" "deadbeef" producing))
        `shouldEqual` Right (Just producing)

    it "writes no rank at all, now that position identifies nothing" do
      let written = stringify $ Progress.toJson "es" "deadbeef" $ Progress.empty # entry "yo" 3 5
      written `shouldSatisfy` \w -> not $ String.contains (String.Pattern "rank") w

    -- Payloads up to v4 name their card by position. Turning that back into a
    -- word needs the deck, so it is `Flashcards.Deck.adopt` that finishes the
    -- job; here the point is only that the rank survives decoding intact.
    it "reads a v4 payload, which is keyed by rank" do
      let decoded = decode """{"version":4,"deck":"deadbeef","cards":[{"rank":4,"box":2,"due":1000,"seen":6,"lapses":2,"missed":3,"direction":"production"}]}"""
      (map _.rank <<< _.cards <$> decoded) `shouldEqual` Right [ Just (Rank 4) ]
      (map _.slug <<< _.cards <$> decoded) `shouldEqual` Right [ Nothing ]
      (map (_.direction <<< _.progress) <<< _.cards <$> decoded) `shouldEqual` Right [ Production ]

    it "reads a v3 payload, which predates directions" do
      let decoded = decode """{"version":3,"deck":"deadbeef","cards":[{"rank":4,"box":2,"due":1000,"seen":6,"lapses":2,"missed":3}]}"""
      -- Every card started life in recognition, so that is the honest default.
      (map (_.direction <<< _.progress) <<< _.cards <$> decoded) `shouldEqual` Right [ Recognition ]

    it "reads a v2 payload, which predates the miss count" do
      let decoded = decode """{"version":2,"deck":"deadbeef","cards":[{"rank":4,"box":1,"due":1000,"seen":6,"lapses":2}]}"""
      -- Absent history reads as zero rather than being invented.
      (map (_.missed <<< _.progress) <<< _.cards <$> decoded) `shouldEqual` Right [ 0 ]

    it "reads a v1 payload, which predates the deck fingerprint" do
      let decoded = decode """{"version":1,"cards":[{"rank":7,"box":2,"due":1000,"seen":3,"lapses":1}]}"""
      (_.deck <$> decoded) `shouldEqual` Right Nothing
      (map (_.seen <<< _.progress) <<< _.cards <$> decoded) `shouldEqual` Right [ 3 ]

    it "refuses a payload written by a newer version" do
      decode """{"version":99,"cards":[]}""" `shouldSatisfy` isLeft
