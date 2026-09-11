module Test.Flashcards.MilestoneSpec
  ( spec
  )
  where

import Prelude

import Data.Maybe (Maybe(..))
import Flashcards.Milestone (Fanfare(..), Milestone(..))
import Flashcards.Milestone as Milestone
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

standing :: Int -> Int -> Milestone.Standing
standing mastered seen = { mastered, seen, total: 1000 }

-- | A session of twenty with nothing missed, which on its own is the smallest
-- | milestone there is — so tests of the larger ones have to beat it.
clean :: Milestone.Tally
clean = { answered: 20, again: 0 }

scrappy :: Milestone.Tally
scrappy = { answered: 20, again: 4 }

reached :: Milestone.Standing -> Milestone.Standing -> Milestone.Tally -> Maybe Milestone
reached = Milestone.reached 20

spec :: Spec Unit
spec = do
  describe "what a session came to" do
    it "is nothing, most of the time" do
      reached (standing 40 300) (standing 42 320) scrappy `shouldEqual` Nothing

    it "notices the first word that stuck" do
      reached (standing 0 60) (standing 1 80) scrappy `shouldEqual` Just FirstMastered

    it "and every hundred after that" do
      reached (standing 98 400) (standing 101 420) scrappy `shouldEqual` Just (Hundred 100)
      reached (standing 799 900) (standing 803 900) scrappy `shouldEqual` Just (Hundred 800)

    it "but not a hundred that was already passed" do
      reached (standing 101 420) (standing 140 460) scrappy `shouldEqual` Nothing

    it "counts meeting the whole deck" do
      reached (standing 300 980) (standing 305 1000) scrappy
        `shouldEqual` Just (EveryWordSeen 1000)

    it "and finishing it" do
      reached (standing 995 1000) (standing 1000 1000) scrappy
        `shouldEqual` Just (Everything 1000)

    -- Crossing the last hundred *is* finishing the deck, and meeting every
    -- word is usually several hundreds at once. Announcing the smaller of the
    -- two would make the larger one smaller.
    it "says only the biggest thing that happened" do
      reached (standing 900 1000) (standing 1000 1000) clean
        `shouldEqual` Just (Everything 1000)
      reached (standing 90 900) (standing 105 1000) clean
        `shouldEqual` Just (EveryWordSeen 1000)

    it "falls back to a clean sweep when nothing larger happened" do
      reached (standing 40 300) (standing 42 320) clean
        `shouldEqual` Just (NothingMissed 20)

    -- Early on nearly every answer is right, because a word got right on
    -- first sight fast-tracks. Without a floor the smallest tier would fire
    -- almost every session and stop meaning anything.
    it "and not for a handful of cards" do
      reached (standing 40 300) (standing 42 320) { answered: 3, again: 0 }
        `shouldEqual` Nothing

    it "nor for an empty session" do
      reached (standing 40 300) (standing 40 300) { answered: 0, again: 0 }
        `shouldEqual` Nothing

  describe "how loudly to say it" do
    it "saves the noise for the things that happen twice" do
      Milestone.fanfare (Everything 1000) `shouldEqual` Burst
      Milestone.fanfare (EveryWordSeen 1000) `shouldEqual` Burst

    it "marks the ten with something smaller" do
      Milestone.fanfare (Hundred 300) `shouldEqual` Flourish

    it "and lets the rest be a sentence" do
      Milestone.fanfare FirstMastered `shouldEqual` Remark
      Milestone.fanfare (NothingMissed 20) `shouldEqual` Remark

  describe "what it says" do
    -- Stated as a fact. Being congratulated by a flashcard is a different app.
    it "reports rather than praises" do
      Milestone.describe (Hundred 200) `shouldEqual` "That makes 200 words mastered."
      Milestone.describe (EveryWordSeen 1000) `shouldEqual` "You have now met all 1000 words."
      Milestone.describe (NothingMissed 20) `shouldEqual` "20 out of 20."
