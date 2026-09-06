module Test.Flashcards.SchedulerSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.DateTime.Instant (Instant, instant, unInstant)
import Data.Maybe (Maybe(..), fromJust)
import Data.Newtype (unwrap)
import Data.Time.Duration (Milliseconds(..))
import Flashcards.Scheduler as Scheduler
import Flashcards.Types.Card (Card, Rank(..))
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress (CardProgress, Progress)
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

-- | The English and Spanish sides are irrelevant to scheduling.
deck :: Array Card
deck = Array.range 1 50 <#> \n ->
  { rank: Rank n, english: "en" <> show n, word: "es" <> show n, example: "" }

reviewed :: Int -> Int -> Number -> Progress -> Progress
reviewed rank box due = Progress.insert (Rank rank) { box, due: at due, seen: 1, lapses: 0, missed: 0, direction: Recognition }

boxedAt :: Int -> Maybe CardProgress
boxedAt box = Just { box, due: at $ 99.0 * day, seen: 4, lapses: 2, missed: 3, direction: Recognition }

-- | Most of these concern a card free to move to production.
graded :: Grade -> Instant -> Maybe CardProgress -> CardProgress
graded grade at' = Scheduler.applyGrade grade at' Scheduler.MayGraduate

-- | Days from `now` until the card is next due.
dueInDays :: CardProgress -> Number
dueInDays cp = (unwrap (unInstant cp.due) - unwrap (unInstant now)) / day

spec :: Spec Unit
spec = do
  describe "buildSession" do
    it "starts a new learner on the most frequent words" do
      Scheduler.buildSession deck Progress.empty now 5 `shouldEqual` (Rank <$> [ 1, 2, 3, 4, 5 ])

    it "caps the queue at the requested size" do
      Array.length (Scheduler.buildSession deck Progress.empty now 20) `shouldEqual` 20

    it "puts due reviews ahead of new words" do
      let progress = Progress.empty # reviewed 30 2 (99.0 * day)
      Scheduler.buildSession deck progress now 3 `shouldEqual` (Rank <$> [ 30, 1, 2 ])

    it "orders due reviews by how overdue they are" do
      let
        progress = Progress.empty
          # reviewed 10 1 (99.0 * day)
          # reviewed 20 1 (95.0 * day)
          # reviewed 30 1 (98.0 * day)
      Array.take 3 (Scheduler.buildSession deck progress now 10)
        `shouldEqual` (Rank <$> [ 20, 30, 10 ])

    it "leaves a card alone until it comes due" do
      let progress = Progress.empty # reviewed 7 3 (105.0 * day)
      Scheduler.buildSession deck progress now 3 `shouldEqual` (Rank <$> [ 1, 2, 3 ])

  describe "applyGrade" do
    it "fast-tracks a word you knew on sight, skipping the short intervals" do
      let cp = graded GotIt now Nothing
      cp.box `shouldEqual` Scheduler.firstSightingBox
      dueInDays cp `shouldEqual` 7.0

    it "promotes one box at a time once a word has been struggled with" do
      -- Missing it first means the next success is ordinary progress, not a
      -- sign you already knew the word.
      let missed = graded Again now Nothing
      missed.box `shouldEqual` 0
      let recovered = graded GotIt now (Just missed)
      recovered.box `shouldEqual` 1
      dueInDays recovered `shouldEqual` 1.0

    it "caps promotion at the last box" do
      -- Only reachable in production now: a recognition card graduates before
      -- it can climb this high.
      let
        retiring = Just { box: Scheduler.maxBox, due: at 0.0, seen: 12, lapses: 1, missed: 4, direction: Production }
        cp = graded GotIt now retiring
      cp.box `shouldEqual` Scheduler.maxBox
      dueInDays cp `shouldEqual` 60.0

    it "tops recognition out below the graduation box, so the long intervals belong to production" do
      let climbed = graded GotIt now $ boxedAt (Scheduler.graduationBox - 2)
      climbed.box `shouldEqual` (Scheduler.graduationBox - 1)
      climbed.direction `shouldEqual` Recognition
      dueInDays climbed `shouldEqual` 7.0

    it "sends a missed card back to box 0, due immediately" do
      let cp = graded Again now $ boxedAt 3
      cp.box `shouldEqual` 0
      dueInDays cp `shouldEqual` 0.0

    it "counts a lapse when a promoted card is missed" do
      (graded Again now $ boxedAt 3).lapses `shouldEqual` 3

    it "does not count a lapse on a word that was never learned" do
      (graded Again now Nothing).lapses `shouldEqual` 0

    it "does count it as a miss, though — accuracy should not flatter you" do
      (graded Again now Nothing).missed `shouldEqual` 1

    it "tallies every wrong answer, learned or not" do
      (graded Again now $ boxedAt 3).missed `shouldEqual` 4

    it "leaves the tally alone on a right answer" do
      (graded GotIt now $ boxedAt 3).missed `shouldEqual` 3

    it "counts every answer as a sighting" do
      (graded Again now $ boxedAt 3).seen `shouldEqual` 5
      (graded GotIt now Nothing).seen `shouldEqual` 1

  describe "graduating to production" do
    it "flips direction on the answer that would reach the graduation box" do
      let cp = graded GotIt now $ boxedAt (Scheduler.graduationBox - 1)
      cp.direction `shouldEqual` Production

    it "restarts the box, because producing is a skill you have not shown yet" do
      let cp = graded GotIt now $ boxedAt (Scheduler.graduationBox - 1)
      cp.box `shouldEqual` Scheduler.productionStartBox
      dueInDays cp `shouldEqual` 1.0

    it "leaves a card in recognition until it has earned the move" do
      let cp = graded GotIt now $ boxedAt (Scheduler.graduationBox - 2)
      cp.direction `shouldEqual` Recognition

    it "never graduates on a first sighting, however well it went" do
      let cp = graded GotIt now Nothing
      cp.direction `shouldEqual` Recognition

    it "does not graduate a card you just got wrong" do
      let cp = graded Again now $ boxedAt (Scheduler.graduationBox - 1)
      cp.direction `shouldEqual` Recognition
      cp.box `shouldEqual` 0

    it "keeps climbing normally once in production" do
      let
        producing = Just { box: 2, due: at 0.0, seen: 9, lapses: 1, missed: 4, direction: Production }
        cp = graded GotIt now producing
      cp.direction `shouldEqual` Production
      cp.box `shouldEqual` 3

    it "sends a missed production card back to box 0 without demoting the skill" do
      let
        producing = Just { box: 3, due: at 0.0, seen: 9, lapses: 1, missed: 4, direction: Production }
        cp = graded Again now producing
      cp.direction `shouldEqual` Production
      cp.box `shouldEqual` 0

    it "takes a known word to production in two answers, an unknown one in four" do
      let
        step cp _ = Just $ graded GotIt now cp
        after n = Array.foldl step Nothing (Array.replicate n unit)
      (_.direction <$> after 1) `shouldEqual` Just Recognition
      (_.direction <$> after 2) `shouldEqual` Just Production

  describe "the whole ladder, end to end" do
    -- Answer each card exactly when it comes due, and record the day it next
    -- falls due along with where it sits. This is the schedule a person
    -- actually experiences.
    let
      walk grades = _.steps $ Array.foldl step { day: 0.0, previous: Nothing, steps: [] } grades
        where
          step acc grade =
            let
              cp = graded grade (at $ acc.day * day) acc.previous
              nextDay = unwrap (unInstant cp.due) / day
            in
              { day: nextDay
              , previous: Just cp
              , steps: acc.steps <>
                  [ { onDay: acc.day
                    , nextIn: nextDay - acc.day
                    , box: cp.box
                    , producing: cp.direction == Production
                    }
                  ]
              }

    it "a word you already knew reaches production on the second answer" do
      map (\s -> s.onDay) (walk [ GotIt, GotIt, GotIt, GotIt, GotIt, GotIt ])
        `shouldEqual` [ 0.0, 7.0, 8.0, 11.0, 18.0, 39.0 ]

    it "and is fully retired after six" do
      map (\s -> s.box) (walk [ GotIt, GotIt, GotIt, GotIt, GotIt, GotIt ])
        `shouldEqual` [ 3, 1, 2, 3, 4, 5 ]

    it "graduating on the second answer, then climbing in production" do
      map (\s -> s.producing) (walk [ GotIt, GotIt, GotIt, GotIt, GotIt, GotIt ])
        `shouldEqual` [ false, true, true, true, true, true ]

    it "a word you have to learn takes four answers to graduate" do
      let learned = walk [ Again, GotIt, GotIt, GotIt, GotIt, GotIt, GotIt, GotIt ]
      map (\s -> s.onDay) learned `shouldEqual` [ 0.0, 0.0, 1.0, 4.0, 11.0, 12.0, 15.0, 22.0 ]
      map (\s -> s.producing) learned
        `shouldEqual` [ false, false, false, false, true, true, true, true ]

    it "missing one in production costs you the ladder, not the direction" do
      let slipped = walk [ GotIt, GotIt, GotIt, Again, GotIt ]
      map (\s -> s.box) slipped `shouldEqual` [ 3, 1, 2, 0, 1 ]
      map (\s -> s.producing) slipped `shouldEqual` [ false, true, true, true, true ]
      -- Box 0 is due immediately: it comes back in the same session.
      map (\s -> s.nextIn) slipped `shouldEqual` [ 7.0, 1.0, 3.0, 0.0, 1.0 ]

    it "a card barred from production never graduates, however well it goes" do
      let
        cp = Scheduler.applyGrade GotIt now Scheduler.RecognitionOnly $
          boxedAt (Scheduler.graduationBox - 1)
      cp.direction `shouldEqual` Recognition
      cp.box `shouldEqual` Scheduler.graduationBox

    it "and climbs the full ladder instead of stopping at the graduation box" do
      let
        climb prev _ = Just $ Scheduler.applyGrade GotIt now Scheduler.RecognitionOnly prev
        after n = Array.foldl climb Nothing (Array.replicate n unit)
      (_.box <$> after 6) `shouldEqual` Just Scheduler.maxBox
      (_.direction <$> after 6) `shouldEqual` Just Recognition

    it "which is a box a graduating card can never reach" do
      let
        climb prev _ = Just $ graded GotIt now prev
        after n = Array.foldl climb Nothing (Array.replicate n unit)
      (_.box <$> after 6) `shouldEqual` Just Scheduler.maxBox
      (_.direction <$> after 6) `shouldEqual` Just Production

  describe "requeue" do
    it "brings a missed card back five cards later" do
      Scheduler.requeue (Rank 99) 0 (Rank <$> [ 1, 2, 3, 4, 5, 6, 7, 8 ])
        `shouldEqual` (Rank <$> [ 1, 2, 3, 4, 5, 99, 6, 7, 8 ])

    it "appends when the session is nearly over" do
      Scheduler.requeue (Rank 99) 6 (Rank <$> [ 1, 2, 3, 4, 5, 6, 7, 8 ])
        `shouldEqual` (Rank <$> [ 1, 2, 3, 4, 5, 6, 7, 8, 99 ])
