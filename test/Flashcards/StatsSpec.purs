module Test.Flashcards.StatsSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.DateTime.Instant (Instant, instant)
import Data.Maybe (Maybe(..), fromJust)
import Data.Time.Duration (Milliseconds(..))
import Flashcards.Stats as Stats
import Flashcards.Types.Card (Card, Rank(..))
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress
import Partial.Unsafe (unsafePartial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

day :: Number
day = 86400000.0

at :: Number -> Instant
at ms = unsafePartial $ fromJust $ instant $ Milliseconds ms

now :: Instant
now = at $ 100.0 * day

deck :: Array Card
deck = Array.range 1 20 <#> \n ->
  { rank: Rank n, english: "en" <> show n, spanish: "es" <> show n }

-- | rank, box, seen, missed, lapses, days until due
card :: Int -> Int -> Int -> Int -> Int -> Number -> Progress -> Progress
card rank box seen missed lapses dueIn =
  Progress.insert (Rank rank)
    { box, seen, missed, lapses, due: at $ (100.0 + dueIn) * day, direction: Recognition }

spec :: Spec Unit
spec = do
  describe "mastery buckets" do
    it "calls an untouched word unseen" do
      Stats.masteryOf Nothing `shouldEqual` Stats.Unseen

    it "treats the short boxes as still being learned" do
      Stats.masteryOf (Just { box: 0, seen: 1, missed: 1, lapses: 0, due: now, direction: Recognition })
        `shouldEqual` Stats.Learning
      Stats.masteryOf (Just { box: 1, seen: 1, missed: 0, lapses: 0, due: now, direction: Recognition })
        `shouldEqual` Stats.Learning

    it "counts the week-and-three-week boxes as familiar" do
      Stats.masteryOf (Just { box: 2, seen: 1, missed: 0, lapses: 0, due: now, direction: Recognition })
        `shouldEqual` Stats.Familiar
      Stats.masteryOf (Just { box: 3, seen: 1, missed: 0, lapses: 0, due: now, direction: Recognition })
        `shouldEqual` Stats.Familiar

    it "only calls the long boxes mastered" do
      Stats.masteryOf (Just { box: 4, seen: 1, missed: 0, lapses: 0, due: now, direction: Recognition })
        `shouldEqual` Stats.Mastered
      Stats.masteryOf (Just { box: 5, seen: 1, missed: 0, lapses: 0, due: now, direction: Recognition })
        `shouldEqual` Stats.Mastered

  describe "frequency bands" do
    it "slices the deck into bands of the requested size" do
      map (\b -> b.from <> "-" <> b.to) (bandLabels 5) `shouldEqual` [ "1-5", "6-10", "11-15", "16-20" ]

    it "clips the final band to the deck rather than overrunning" do
      map (\b -> b.from <> "-" <> b.to) (bandLabels 7) `shouldEqual` [ "1-7", "8-14", "15-20" ]

    it "accounts for every word in the band" do
      let
        progress = Progress.empty # card 1 5 3 0 0 30.0 # card 2 0 1 1 0 0.0
        counts = _.counts <$> Array.head (Stats.bands 5 deck progress)
      (map (\c -> c.unseen + c.learning + c.familiar + c.mastered) counts) `shouldEqual` Just 5

    it "places each word in the right bucket" do
      let
        progress = Progress.empty
          # card 1 5 3 0 0 30.0
          # card 2 3 2 0 0 5.0
          # card 3 0 1 1 0 0.0
        counts = _.counts <$> Array.head (Stats.bands 5 deck progress)
      counts `shouldEqual` Just { unseen: 2, learning: 1, familiar: 1, mastered: 1 }

    it "shows an untouched deck as entirely unseen" do
      let counts = _.counts <$> Array.head (Stats.bands 5 deck Progress.empty)
      counts `shouldEqual` Just { unseen: 5, learning: 0, familiar: 0, mastered: 0 }

  describe "overview" do
    it "has no accuracy to report before anything is answered" do
      (Stats.overview now deck Progress.empty).accuracy `shouldEqual` Nothing

    it "computes accuracy from every wrong answer, not just lapses" do
      -- 10 answers, 3 of them wrong.
      let progress = Progress.empty # card 1 2 10 3 1 5.0
      (Stats.overview now deck progress).accuracy `shouldEqual` Just 70.0

    it "counts what is due now separately from tomorrow" do
      let
        progress = Progress.empty
          # card 1 1 1 0 0 (-1.0)
          # card 2 1 1 0 0 0.5
          # card 3 1 1 0 0 3.0
        o = Stats.overview now deck progress
      o.dueNow `shouldEqual` 1
      o.dueTomorrow `shouldEqual` 1

    it "counts only words that are mastered" do
      let progress = Progress.empty # card 1 4 1 0 0 30.0 # card 2 3 1 0 0 5.0
      (Stats.overview now deck progress).mastered `shouldEqual` 1

    it "ignores history for words no longer in the deck" do
      -- A rank beyond the deck must not inflate the totals.
      let progress = Progress.empty # card 1 2 4 1 0 5.0 # card 999 5 50 20 9 5.0
      (Stats.overview now deck progress).answers `shouldEqual` 4
      (Stats.overview now deck progress).seen `shouldEqual` 1

  describe "leeches" do
    it "surfaces words that keep slipping, worst first" do
      let
        progress = Progress.empty
          # card 1 1 9 5 3 1.0
          # card 2 1 9 9 6 1.0
        found = Stats.leeches 3 deck progress
      map _.lapses found `shouldEqual` [ 6, 3 ]
      map _.spanish found `shouldEqual` [ "es2", "es1" ]

    it "leaves ordinary forgetting alone" do
      let progress = Progress.empty # card 1 1 9 5 2 1.0
      Stats.leeches 3 deck progress `shouldEqual` []

    it "judges on lapses, not on a hard first encounter" do
      -- Missed eight times while learning, never forgotten since.
      let progress = Progress.empty # card 1 3 9 8 0 1.0
      Stats.leeches 3 deck progress `shouldEqual` []
  where
    bandLabels size = map (\b -> { from: show b.from, to: show b.to }) (Stats.bands size deck Progress.empty)
