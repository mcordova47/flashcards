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
  { rank: Rank n, english: "en" <> show n, spanish: "es" <> show n }

reviewed :: Int -> Int -> Number -> Progress -> Progress
reviewed rank box due = Progress.insert (Rank rank) { box, due: at due, seen: 1, lapses: 0 }

boxedAt :: Int -> Maybe CardProgress
boxedAt box = Just { box, due: at $ 99.0 * day, seen: 4, lapses: 2 }

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
      let cp = Scheduler.applyGrade GotIt now Nothing
      cp.box `shouldEqual` Scheduler.firstSightingBox
      dueInDays cp `shouldEqual` 7.0

    it "promotes one box at a time once a word has been struggled with" do
      -- Missing it first means the next success is ordinary progress, not a
      -- sign you already knew the word.
      let missed = Scheduler.applyGrade Again now Nothing
      missed.box `shouldEqual` 0
      let recovered = Scheduler.applyGrade GotIt now (Just missed)
      recovered.box `shouldEqual` 1
      dueInDays recovered `shouldEqual` 1.0

    it "caps promotion at the last box" do
      let cp = Scheduler.applyGrade GotIt now $ boxedAt Scheduler.maxBox
      cp.box `shouldEqual` Scheduler.maxBox
      dueInDays cp `shouldEqual` 60.0

    it "sends a missed card back to box 0, due immediately" do
      let cp = Scheduler.applyGrade Again now $ boxedAt 3
      cp.box `shouldEqual` 0
      dueInDays cp `shouldEqual` 0.0

    it "counts a lapse when a promoted card is missed" do
      (Scheduler.applyGrade Again now $ boxedAt 3).lapses `shouldEqual` 3

    it "does not count a lapse on a word that was never learned" do
      (Scheduler.applyGrade Again now Nothing).lapses `shouldEqual` 0

    it "counts every answer as a sighting" do
      (Scheduler.applyGrade Again now $ boxedAt 3).seen `shouldEqual` 5
      (Scheduler.applyGrade GotIt now Nothing).seen `shouldEqual` 1

  describe "requeue" do
    it "brings a missed card back five cards later" do
      Scheduler.requeue (Rank 99) 0 (Rank <$> [ 1, 2, 3, 4, 5, 6, 7, 8 ])
        `shouldEqual` (Rank <$> [ 1, 2, 3, 4, 5, 99, 6, 7, 8 ])

    it "appends when the session is nearly over" do
      Scheduler.requeue (Rank 99) 6 (Rank <$> [ 1, 2, 3, 4, 5, 6, 7, 8 ])
        `shouldEqual` (Rank <$> [ 1, 2, 3, 4, 5, 6, 7, 8, 99 ])
