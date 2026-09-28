module Test.Flashcards.PorParaSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmpty
import Data.Maybe (Maybe(..))
import Data.Set as Set
import Flashcards.Data.Paraphrase.Spanish (prompts)
import Flashcards.Data.PorPara.Spanish (sentences)
import Flashcards.Data.Sentences.Spanish as Bank
import Flashcards.Data.Verbs.Spanish (table)
import Flashcards.Exercise (Answer(..), Exercise, pick, pools)
import Flashcards.Types.Card (Slug(..), slugToString)
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Progress (CardProgress)
import Flashcards.Verbs.Paraphrase as Paraphrase
import Flashcards.Verbs.PersonShift as PersonShift
import Flashcards.Verbs.PorPara (Contrast(..), Preposition(..), exercise, exercises)
import Flashcards.Verbs.Shift as Shift
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = do
  describe "a por / para exercise" do
    let e = exercise causeOfYou

    it "is keyed by its contrast, not by its sentence" do
      e.slug `shouldEqual` Slug "porpara.cause-purpose"
      e.label `shouldEqual` "por / para · cause vs purpose"

    -- The typed view heads the page with the prompt. The Spanish would have
    -- the answer in it.
    it "asks the English, which is what says which sense it is" do
      e.prompt `shouldEqual` "I did it because of you."
      e.hint `shouldEqual` "por / para"

    it "with a box where the preposition goes" do
      checked e `shouldEqual` Just { expected: "por", before: "lo hice ", after: " ti" }

    it "and the other side of a pair answers the other way" do
      checked (exercise causeOfYou { answer = Para, english = "I did it for your benefit." })
        `shouldEqual` Just { expected: "para", before: "lo hice ", after: " ti" }

  describe "the bank" do
    let yielded = pools (exercises sentences)

    it "gives one item per contrast, not one per sentence" do
      map (slugToString <<< _.slug) yielded `shouldEqual`
        [ "porpara.cause-purpose", "porpara.duration-deadline"
        , "porpara.through-towards", "porpara.exchange-recipient"
        ]

    -- A pool that is all `por` can be passed by always typing `por`.
    it "asks both sides of every contrast" do
      yielded
        # Array.filter (\p -> Set.size (Set.fromFoldable (NonEmpty.toArray p.exercises >>= answers)) < 2)
        # map (slugToString <<< _.slug)
        # shouldEqual []

    -- Every sighting of a turn asks something different, and the minimal
    -- pairs count as different: their Spanish is one string, and the English
    -- that tells them apart is the prompt.
    it "asks every sentence of a pool once before it asks one again" do
      yielded
        # Array.filter (\p ->
            let n = NonEmpty.length p.exercises
            in Set.size (Set.fromFoldable (Array.range 0 (n - 1) <#> \i -> (pick (Just (seenTimes i)) p).prompt)) /= n)
        # map (slugToString <<< _.slug)
        # shouldEqual []

    it "shares no item with the other drills" do
      let
        others = Set.fromFoldable $ map _.slug $
          Shift.exercises table Bank.sentences
            <> PersonShift.exercises table Bank.sentences
            <> Paraphrase.exercises prompts
      Array.filter (\p -> Set.member p.slug others) yielded # map (slugToString <<< _.slug)
        # shouldEqual []
  where
    causeOfYou =
      { before: "lo hice ", answer: Por, after: " ti"
      , english: "I did it because of you.", contrast: CausePurpose
      }

seenTimes :: Int -> CardProgress
seenTimes n = { box: 1, due: bottom, seen: n, lapses: 0, missed: 0, direction: Recognition }

checked :: Exercise -> Maybe { expected :: String, before :: String, after :: String }
checked e = case e.answer of
  Checked c -> Just { expected: c.expected, before: c.frame.before, after: c.frame.after }
  SelfGraded _ -> Nothing

answers :: Exercise -> Array String
answers e = case e.answer of
  Checked c -> [ c.expected ]
  SelfGraded _ -> []
