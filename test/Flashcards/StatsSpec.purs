module Test.Flashcards.StatsSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.DateTime.Instant (Instant, instant)
import Data.Maybe (Maybe(..), fromJust)
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple.Nested ((/\))
import Flashcards.Scheduler as Scheduler
import Flashcards.Stats as Stats
import Flashcards.Types.Card (Card, Rank(..), Slug(..))
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
  { rank: Rank n, slug: slugAt n, english: "en" <> show n, word: "es" <> show n, example: "" }

slugs :: Array Slug
slugs = map _.slug deck

-- | The slug of the card at rank `n`. Progress is keyed by slug, so the
-- | helpers below take a rank only because it is the readable way to name a
-- | card in a synthetic deck.
slugAt :: Int -> Slug
slugAt n = Slug $ "es" <> show n

-- | An interval of `days` on the `seen`th answer of the card at rank 1, which
-- | is the ladder's moved by the offset: what the forecasts below are a hand
-- | calculation of.
fuzzedDays :: Int -> Number -> Number
fuzzedDays seen days = Scheduler.fuzzed (slugAt 1) seen (Milliseconds $ days * day) # \(Milliseconds ms) -> ms / day

-- | rank, box, seen, missed, lapses, days until due
card :: Int -> Int -> Int -> Int -> Int -> Number -> Progress -> Progress
card = cardIn Recognition

producing :: Int -> Int -> Int -> Int -> Int -> Number -> Progress -> Progress
producing = cardIn Production

cardIn :: Direction -> Int -> Int -> Int -> Int -> Int -> Number -> Progress -> Progress
cardIn direction rank box seen missed lapses dueIn =
  Progress.insert (slugAt rank)
    { box, seen, missed, lapses, due: at $ (100.0 + dueIn) * day, direction }

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

    it "does not call a recognition card mastered on its way up" do
      -- Recognising a word is not knowing it; producing it is.
      Stats.masteryOf (Just { box: 3, seen: 1, missed: 0, lapses: 0, due: now, direction: Recognition })
        `shouldEqual` Stats.Familiar

    it "but does at the very top, where only a card barred from production sits" do
      -- A graduating card leaves recognition at box 3, so this is a card that
      -- shares its English side and has gone as far as it can.
      Stats.masteryOf (Just { box: 5, seen: 9, missed: 1, lapses: 0, due: now, direction: Recognition })
        `shouldEqual` Stats.Mastered

    it "treats a freshly graduated card as familiar, not mastered" do
      Stats.masteryOf (Just { box: 1, seen: 9, missed: 2, lapses: 0, due: now, direction: Production })
        `shouldEqual` Stats.Familiar

    it "calls a word mastered once it can be produced reliably" do
      Stats.masteryOf (Just { box: 3, seen: 9, missed: 2, lapses: 0, due: now, direction: Production })
        `shouldEqual` Stats.Mastered

    it "ranks production above recognition even at a lower box" do
      let
        recognised = Just { box: 3, seen: 4, missed: 0, lapses: 0, due: now, direction: Recognition }
        produced = Just { box: 3, seen: 9, missed: 2, lapses: 0, due: now, direction: Production }
      Stats.masteryOf recognised `shouldEqual` Stats.Familiar
      Stats.masteryOf produced `shouldEqual` Stats.Mastered

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
          # producing 1 3 9 1 0 30.0
          # card 2 3 2 0 0 5.0
          # card 3 0 1 1 0 0.0
        counts = _.counts <$> Array.head (Stats.bands 5 deck progress)
      counts `shouldEqual` Just { unseen: 2, learning: 1, familiar: 1, mastered: 1 }

    it "counts a mid recognition box as familiar, not mastered" do
      let
        progress = Progress.empty # card 1 3 3 0 0 30.0
        counts = _.counts <$> Array.head (Stats.bands 5 deck progress)
      counts `shouldEqual` Just { unseen: 4, learning: 0, familiar: 1, mastered: 0 }

    it "shows an untouched deck as entirely unseen" do
      let counts = _.counts <$> Array.head (Stats.bands 5 deck Progress.empty)
      counts `shouldEqual` Just { unseen: 5, learning: 0, familiar: 0, mastered: 0 }

  describe "overview" do
    it "has no accuracy to report before anything is answered" do
      (Stats.overview now slugs Progress.empty).accuracy `shouldEqual` Nothing

    it "computes accuracy from every wrong answer, not just lapses" do
      -- 10 answers, 3 of them wrong.
      let progress = Progress.empty # card 1 2 10 3 1 5.0
      (Stats.overview now slugs progress).accuracy `shouldEqual` Just 70.0

    it "counts what is due now separately from tomorrow" do
      let
        progress = Progress.empty
          # card 1 1 1 0 0 (-1.0)
          # card 2 1 1 0 0 0.5
          # card 3 1 1 0 0 3.0
        o = Stats.overview now slugs progress
      o.dueNow `shouldEqual` 1
      o.dueTomorrow `shouldEqual` 1

    it "counts only words that can be produced as mastered" do
      let progress = Progress.empty # producing 1 3 9 1 0 30.0 # card 2 3 1 0 0 5.0
      (Stats.overview now slugs progress).mastered `shouldEqual` 1

    it "counts how many words have graduated to production" do
      let progress = Progress.empty # producing 1 1 9 1 0 30.0 # card 2 3 1 0 0 5.0
      (Stats.overview now slugs progress).producing `shouldEqual` 1

    it "ignores history for words no longer in the deck" do
      -- A word that is not in the deck must not inflate the totals.
      let progress = Progress.empty # card 1 2 4 1 0 5.0 # card 999 5 50 20 9 5.0
      (Stats.overview now slugs progress).answers `shouldEqual` 4
      (Stats.overview now slugs progress).seen `shouldEqual` 1

  describe "how long until the next card" do
    it "measures to the soonest card still ahead" do
      let
        progress = Progress.empty
          # card 1 1 1 0 0 3.0
          # card 2 1 1 0 0 0.25
          # card 3 1 1 0 0 9.0
      Stats.nextDueIn now slugs progress `shouldEqual` Just (Milliseconds $ 0.25 * day)

    it "ignores cards already waiting for you" do
      let progress = Progress.empty # card 1 1 1 0 0 (-2.0) # card 2 1 1 0 0 5.0
      Stats.nextDueIn now slugs progress `shouldEqual` Just (Milliseconds $ 5.0 * day)

    it "has nothing to report when everything is already due" do
      let progress = Progress.empty # card 1 1 1 0 0 (-2.0)
      Stats.nextDueIn now slugs progress `shouldEqual` Nothing

    it "has nothing to report on an untouched deck" do
      Stats.nextDueIn now slugs Progress.empty `shouldEqual` Nothing

  describe "when the first item could be mastered" do
    let wait progress = Stats.firstMasteredIn now slugs progress

    it "plays the ladder out from the item that is furthest along" do
      -- Box 4 is one right answer from the top, given when it falls due.
      wait (Progress.empty # card 1 4 1 0 0 5.0 # card 2 3 1 0 0 1.0)
        `shouldEqual` Just (Milliseconds $ 5.0 * day)

    it "adds each rung's interval after the answer that climbs it" do
      -- Box 3 due in 2 days: answered then it is box 4 due 21 days on.
      -- The 21 is the second answer's, offset as that answer's date is.
      wait (Progress.empty # card 1 3 1 0 0 2.0) `shouldEqual` Just (Milliseconds $ (2.0 + fuzzedDays 2 21.0) * day)
      -- Box 2 due in 1: box 3 (+7), box 4 (+21), box 5, on answers 2 and 3.
      wait (Progress.empty # card 1 2 1 0 0 1.0) `shouldEqual` Just (Milliseconds $ (1.0 + fuzzedDays 2 7.0 + fuzzedDays 3 21.0) * day)

    it "answers an overdue item now, not when it fell due" do
      wait (Progress.empty # card 1 4 1 0 0 (-2.0)) `shouldEqual` Just (Milliseconds 0.0)

    it "has nothing to say once something is mastered, or before anything is tracked" do
      wait (Progress.empty # card 1 5 1 0 0 30.0 # card 2 3 1 0 0 2.0) `shouldEqual` Nothing
      wait Progress.empty `shouldEqual` Nothing

  describe "when a number of items could be mastered" do
    let
      item allowed n = { slug: slugAt n, allowed }
      plain = item Scheduler.RecognitionOnly
      graduating = item Scheduler.MayGraduate
      masteredIn target items progress = Stats.masteredIn now target items progress

    -- The shape of the real case: some production cards a few days off and one
    -- that can only climb the recognition ladder, 12 days from its last rung.
    it "is the that-many-th earliest of the ones started" do
      let
        items = map plain [ 1, 2, 3, 4 ]
        progress = Progress.empty
          # producing 1 2 1 0 0 1.0
          # producing 2 1 1 0 0 1.0
          # producing 3 2 1 0 0 1.0
          # card 4 4 1 0 0 12.0
      -- Box 2 answered when due is box 3, which is mastered for production,
      -- so one day. Box 1 answered then is box 2 due 3 days on: 1 + 3 = 4.
      masteredIn 1 items progress `shouldEqual` Just (Milliseconds day)
      masteredIn 2 items progress `shouldEqual` Just (Milliseconds day)
      masteredIn 3 items progress `shouldEqual` Just (Milliseconds $ 4.0 * day)
      masteredIn 4 items progress `shouldEqual` Just (Milliseconds $ 12.0 * day)

    it "counts what is already mastered towards the target" do
      let
        items = map plain [ 1, 2, 3 ]
        progress = Progress.empty # card 1 5 1 0 0 30.0 # card 2 4 1 0 0 5.0 # card 3 4 1 0 0 9.0
      masteredIn 2 items progress `shouldEqual` Just (Milliseconds $ 5.0 * day)
      masteredIn 3 items progress `shouldEqual` Just (Milliseconds $ 9.0 * day)

    it "has nothing to say when the target is already met" do
      let progress = Progress.empty # card 1 5 1 0 0 30.0 # card 2 5 1 0 0 30.0
      masteredIn 2 (map plain [ 1, 2 ]) progress `shouldEqual` Nothing

    -- Unstarted cards have no date, so a target that needs one has no honest
    -- answer, and saying nothing is it.
    it "has nothing to say when too few are started to reach it" do
      let progress = Progress.empty # card 1 4 1 0 0 5.0
      masteredIn 1 (map plain [ 1, 2, 3 ]) progress `shouldEqual` Just (Milliseconds $ 5.0 * day)
      masteredIn 2 (map plain [ 1, 2, 3 ]) progress `shouldEqual` Nothing

    -- Recognition box 3 due in 2 days. Barred from production it climbs to
    -- box 5: 2 days, then 21 to box 4's answer, so 23 in all.
    -- Allowed, it graduates on the answer that would make it box 4: back to
    -- production box 1 (+1), box 2 (+3), box 3 mastered: 2 + 1 + 3 = 6.
    it "follows whether a card may graduate" do
      let progress = Progress.empty # card 1 3 1 0 0 2.0
      masteredIn 1 [ plain 1 ] progress `shouldEqual` Just (Milliseconds $ (2.0 + fuzzedDays 2 21.0) * day)
      masteredIn 1 [ graduating 1 ] progress `shouldEqual` Just (Milliseconds $ 6.0 * day)

    it "answers an overdue card now, not when it fell due" do
      masteredIn 1 [ plain 1 ] (Progress.empty # card 1 4 1 0 0 (-3.0))
        `shouldEqual` Just (Milliseconds 0.0)

  describe "which are left to master" do
    let
      item allowed n = { slug: slugAt n, allowed }
      left = Stats.leftToMaster now (map (item Scheduler.RecognitionOnly) [ 1, 2, 3, 4 ])

    it "lists the started, unmastered ones, soonest first" do
      let
        progress = Progress.empty
          # card 1 4 1 0 0 12.0
          # card 2 4 1 0 0 5.0
          # card 3 5 1 0 0 30.0
      map (\l -> l.item.slug /\ l.wait) (left progress)
        `shouldEqual` [ slugAt 2 /\ Milliseconds (5.0 * day), slugAt 1 /\ Milliseconds (12.0 * day) ]

    it "puts the one that has slipped most first among equals" do
      let
        progress = Progress.empty # card 1 4 5 1 2 5.0 # card 2 4 9 6 7 5.0
      map _.lapses (left progress) `shouldEqual` [ 7, 2 ]

    it "leaves out what has not been started" do
      left Progress.empty `shouldEqual` []

  describe "describing a wait" do
    it "does not bother with seconds" do
      Stats.describeDuration (Milliseconds 20000.0) `shouldEqual` "under a minute"

    it "counts minutes, then hours, then days" do
      Stats.describeDuration (Milliseconds $ 25.0 * 60000.0) `shouldEqual` "25 minutes"
      Stats.describeDuration (Milliseconds $ 4.0 * 3600000.0) `shouldEqual` "4 hours"
      Stats.describeDuration (Milliseconds $ 3.0 * day) `shouldEqual` "3 days"

    it "says one of a thing without an s" do
      Stats.describeDuration (Milliseconds 60000.0) `shouldEqual` "1 minute"
      Stats.describeDuration (Milliseconds 3600000.0) `shouldEqual` "1 hour"
      Stats.describeDuration (Milliseconds day) `shouldEqual` "1 day"

    it "rolls up rather than saying 60 minutes or 24 hours" do
      Stats.describeDuration (Milliseconds $ 59.7 * 60000.0) `shouldEqual` "1 hour"
      Stats.describeDuration (Milliseconds $ 23.8 * 3600000.0) `shouldEqual` "1 day"

  describe "saying when" do
    it "says now when nothing but what is due stands in the way" do
      Stats.describeEarliest (Milliseconds 0.0) `shouldEqual` "now"

    it "otherwise says how long, as a wait" do
      Stats.describeEarliest (Milliseconds $ 12.0 * day) `shouldEqual` "in 12 days"
      Stats.describeEarliest (Milliseconds $ 5.0 * 3600000.0) `shouldEqual` "in 5 hours"

  describe "counting things" do
    -- The session tally read "1 cards" from the day it was written, which is
    -- every time exactly one card comes due.
    it "says one card and two cards" do
      Stats.plural 1 "card" `shouldEqual` "1 card"
      Stats.plural 2 "card" `shouldEqual` "2 cards"
      Stats.plural 0 "card" `shouldEqual` "0 cards"

  describe "leeches" do
    it "surfaces words that keep slipping, worst first" do
      let
        progress = Progress.empty
          # card 1 1 9 5 3 1.0
          # card 2 1 9 9 6 1.0
        found = Stats.leeches 3 deck progress
      map _.lapses found `shouldEqual` [ 6, 3 ]
      map _.word found `shouldEqual` [ "es2", "es1" ]
      -- The slug is what a drill session is built from, so it has to come out
      -- of here rather than being looked up again from the word.
      map _.slug found `shouldEqual` (slugAt <$> [ 2, 1 ])

    it "leaves ordinary forgetting alone" do
      let progress = Progress.empty # card 1 1 9 5 2 1.0
      Stats.leeches 3 deck progress `shouldEqual` []

    -- `lapses` never comes down, so on its own it lists every word that ever
    -- qualified. The heading is present tense; the list has to be too.
    it "forgets a word that has climbed back up" do
      let progress = Progress.empty # card 1 4 20 6 5 20.0
      Stats.leeches 3 deck progress `shouldEqual` []

    it "and one that has settled at the harder question" do
      let progress = Progress.empty # producing 1 3 20 6 5 20.0
      Stats.leeches 3 deck progress `shouldEqual` []

    -- Where a production leech actually sits. Box 0 is due immediately and
    -- requeued into the same session, so it is answered again and climbs to 1
    -- before the session ends.
    it "but keeps one that is failing at the harder question" do
      let progress = Progress.empty # producing 1 1 20 6 5 (-0.1)
      map _.word (Stats.leeches 3 deck progress) `shouldEqual` [ "es1" ]

    it "judges on lapses, not on a hard first encounter" do
      -- Missed eight times while learning, never forgotten since.
      let progress = Progress.empty # card 1 3 9 8 0 1.0
      Stats.leeches 3 deck progress `shouldEqual` []
  where
    bandLabels size = map (\b -> { from: show b.from, to: show b.to }) (Stats.bands size deck Progress.empty)
