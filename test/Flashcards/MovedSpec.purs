module Test.Flashcards.MovedSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.DateTime.Instant (Instant, instant)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromJust, maybe)
import Data.Time.Duration (Milliseconds(..))
import Flashcards.Moved as Moved
import Flashcards.Types.Card (Slug(..))
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress
import Partial.Unsafe (unsafePartial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

now :: Instant
now = unsafePartial $ fromJust $ instant $ Milliseconds 0.0

put :: String -> Int -> Progress -> Progress
put slug box = Progress.insert (Slug slug)
  { box, seen: 1, missed: 0, lapses: 0, due: now, direction: Recognition }

-- | What the session saw of each item before answering it, then what became of it.
session :: Array { slug :: String, was :: Maybe Int, now :: Int } -> Moved.Moved
session answered = Moved.moved before after
  where
    before = Array.foldl (\b a -> Moved.remember (Slug a.slug) (maybe Progress.empty (\box -> put a.slug box Progress.empty) a.was) b) Map.empty answered
    after = Array.foldl (\p a -> put a.slug a.now p) Progress.empty answered

spec :: Spec Unit
spec = describe "what a session moved" do
  it "counts items that went up, were met, and fell back, separately" do
    session
      [ { slug: "a", was: Just 3, now: 4 }
      , { slug: "b", was: Just 2, now: 3 }
      , { slug: "c", was: Nothing, now: 3 }
      , { slug: "d", was: Just 4, now: 1 }
      , { slug: "e", was: Just 3, now: 3 }
      ]
      `shouldEqual` { climbed: 2, met: 1, fell: 1 }

  it "calls an item new to the session met, not climbed, however far it landed" do
    session [ { slug: "a", was: Nothing, now: 3 } ] `shouldEqual` { climbed: 0, met: 1, fell: 0 }

  it "remembers an item as it was the first time, not the second" do
    let
      first = Moved.remember (Slug "a") (put "a" 3 Progress.empty) Map.empty
      -- Answered once already, now at 5, and remembered again at the second answer.
      again = Moved.remember (Slug "a") (put "a" 5 Progress.empty) first
    -- From 3 it is now 4, a climb. Had the second sighting replaced the first,
    -- it would have gone 5 to 4 and read as a fall.
    Moved.moved again (put "a" 4 Progress.empty) `shouldEqual` { climbed: 1, met: 0, fell: 0 }

  describe "saying so" do
    it "says nothing where nothing moved" do
      Moved.describe { climbed: 0, met: 0, fell: 0 } `shouldEqual` Nothing

    it "names only what happened" do
      Moved.describe { climbed: 14, met: 0, fell: 2 } `shouldEqual` Just "14 climbed a box · 2 fell back"
      Moved.describe { climbed: 0, met: 1, fell: 0 } `shouldEqual` Just "1 new item met"
