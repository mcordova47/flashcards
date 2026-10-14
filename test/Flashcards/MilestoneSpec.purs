module Test.Flashcards.MilestoneSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Flashcards.Milestone (Fanfare(..), Milestone(..))
import Flashcards.Milestone as Milestone
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

standing :: Int -> Int -> Milestone.Standing
standing mastered seen = { mastered, seen, slipping: 0, total: 1000 }

slipping :: Int -> Milestone.Standing -> Milestone.Standing
slipping n s = s { slipping = n }

reached :: Milestone.Standing -> Milestone.Standing -> Maybe Milestone
reached = Milestone.reached

spec :: Spec Unit
spec = do
  describe "what a session came to" do
    it "is nothing, most of the time" do
      reached (standing 40 300) (standing 42 320) `shouldEqual` Nothing

    it "notices the first word that stuck" do
      reached (standing 0 60) (standing 1 80) `shouldEqual` Just FirstMastered

    it "and every hundred after that" do
      reached (standing 98 400) (standing 101 420) `shouldEqual` Just (Hundred 100)
      reached (standing 799 900) (standing 803 900) `shouldEqual` Just (Hundred 800)

    it "but not a hundred that was already passed" do
      reached (standing 101 420) (standing 140 460) `shouldEqual` Nothing

    it "counts meeting the whole deck" do
      reached (standing 300 980) (standing 305 1000)
        `shouldEqual` Just (EveryWordSeen 1000)

    it "and finishing it" do
      reached (standing 995 1000) (standing 1000 1000)
        `shouldEqual` Just (Everything 1000)

    -- Crossing the last hundred *is* finishing the deck, and meeting every
    -- word is usually several hundreds at once. Announcing the smaller of the
    -- two would make the larger one smaller.
    it "says only the biggest thing that happened" do
      reached (standing 900 1000) (standing 1000 1000)
        `shouldEqual` Just (Everything 1000)
      reached (standing 90 900) (standing 105 1000)
        `shouldEqual` Just (EveryWordSeen 1000)

    -- The one repeatable milestone, and the only one about words getting
    -- better rather than about totals getting bigger.
    it "notices the last slipping word coming good" do
      reached (slipping 3 $ standing 40 300) (standing 42 320)
        `shouldEqual` Just Recovered

    it "but not while any are still slipping" do
      reached (slipping 3 $ standing 40 300) (slipping 1 $ standing 42 320)
        `shouldEqual` Nothing

    it "nor when there were none to begin with" do
      reached (standing 40 300) (standing 42 320) `shouldEqual` Nothing

  describe "how loudly to say it" do
    it "saves the noise for the things that happen twice" do
      Milestone.fanfare (Everything 1000) `shouldEqual` Burst
      Milestone.fanfare (EveryWordSeen 1000) `shouldEqual` Burst

    it "marks the ten with something smaller" do
      Milestone.fanfare (Hundred 300) `shouldEqual` Flourish

    it "and lets the rest be a sentence" do
      Milestone.fanfare FirstMastered `shouldEqual` Remark
      Milestone.fanfare Recovered `shouldEqual` Remark

  describe "what it says" do
    -- Stated as a fact. Being congratulated by a flashcard is a different app.
    it "reports rather than praises" do
      Milestone.describe (Hundred 200) `shouldEqual` "You’ve now mastered 200 words!"
      Milestone.describe (EveryWordSeen 1000) `shouldEqual` "You have now met all 1000 words!"
      Milestone.describe Recovered `shouldEqual` "Nothing is slipping any more!"

  describe "the next one a forecast can speak of" do
    let upcoming mastered = Milestone.upcoming { mastered, total: 1000 }

    it "is the first word until there is one" do
      upcoming 0 `shouldEqual` Just { milestone: FirstMastered, needs: 1 }

    it "is the next hundred after that" do
      upcoming 1 `shouldEqual` Just { milestone: Hundred 100, needs: 100 }
      upcoming 100 `shouldEqual` Just { milestone: Hundred 200, needs: 200 }
      upcoming 899 `shouldEqual` Just { milestone: Hundred 900, needs: 900 }

    -- With 983 mastered the next hundred is the whole deck, which is what the
    -- issue's learner sees: `Everything 1000`, 17 more.
    it "is the end of the deck when the next hundred is the deck" do
      upcoming 983 `shouldEqual` Just { milestone: Everything 1000, needs: 1000 }
      Milestone.upcoming { mastered: 910, total: 950 }
        `shouldEqual` Just { milestone: Everything 950, needs: 950 }

    it "is nothing once every word is mastered, or with no deck" do
      upcoming 1000 `shouldEqual` Nothing
      Milestone.upcoming { mastered: 0, total: 0 } `shouldEqual` Nothing

    -- The forecast promises exactly what `reached` would announce: crossing
    -- to `needs` mastered is the milestone named, for every starting point.
    it "names what reaching it would announce" do
      let
        agrees m = case upcoming m of
          Just next -> reached (standing m 0) (standing next.needs 0) == Just next.milestone
          Nothing -> false
      Array.all agrees (Array.range 0 999) `shouldEqual` true
