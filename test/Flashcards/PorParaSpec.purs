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
import Flashcards.Verbs.PorPara (Item(..), Preposition(..), buttons, exercise, exercises, takes, word)
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

  -- #43. A sense with no opposite is the same exercise with a one-sided pool.
  describe "a sense with no opposite" do
    let e = exercise twiceAWeek

    it "is keyed by its sense" do
      e.slug `shouldEqual` Slug "porpara.per"
      e.label `shouldEqual` "por / para · per"

    -- The hint is the answer space. One that told a sense from a contrast
    -- would say `por` here, which is the answer.
    it "still offers the choice, since saying there is none would answer it" do
      e.hint `shouldEqual` "por / para"
      checked e `shouldEqual` Just { expected: "por", before: "llamo a mi madre dos veces ", after: " semana" }

  -- #38. The same question, answered by tapping.
  describe "a por / para exercise answered by buttons" do
    let e = buttons (exercise causeOfYou)

    it "offers por and para, in that order" do
      choice e `shouldEqual` Just { options: [ "por", "para" ], expected: "por", before: "lo hice ", after: " ti" }

    it "keeps everything else of the question" do
      let plain = exercise causeOfYou
      { slug: e.slug, prompt: e.prompt, hint: e.hint, family: e.family }
        `shouldEqual` { slug: plain.slug, prompt: plain.prompt, hint: plain.hint, family: plain.family }

    it "leaves the other drills alone" do
      let shifted = Shift.exercises table Bank.sentences
      Array.any (isChoice <<< _.answer <<< buttons) shifted `shouldEqual` false

  describe "the bank" do
    let yielded = pools (exercises sentences)

    it "gives one item per contrast or sense, not one per sentence" do
      map (slugToString <<< _.slug) yielded `shouldEqual`
        [ "porpara.cause-purpose", "porpara.duration-deadline"
        , "porpara.through-towards", "porpara.exchange-recipient"
        , "porpara.per", "porpara.means"
        ]

    -- A contrast whose pool is all `por` can be passed by always typing
    -- `por`. A sense has one side by definition, and a sentence answered the
    -- other way is in the wrong item.
    it "asks both sides of every contrast, and only its own of every sense" do
      Array.nubEq (map _.item sentences)
        # Array.filter (\i ->
            let sides = Set.fromFoldable (Array.filter (\s -> s.item == i) sentences <#> word <<< _.answer)
            in case takes i of
              Nothing -> Set.size sides < 2
              Just p -> sides /= Set.singleton (word p))
        # map show
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
      , english: "I did it because of you.", item: CausePurpose
      }
    twiceAWeek =
      { before: "llamo a mi madre dos veces ", answer: Por, after: " semana"
      , english: "I call my mother twice a week.", item: Per
      }

seenTimes :: Int -> CardProgress
seenTimes n = { box: 1, due: bottom, seen: n, lapses: 0, missed: 0, direction: Recognition }

checked :: Exercise -> Maybe { expected :: String, before :: String, after :: String }
checked e = case e.answer of
  Checked c -> Just { expected: c.expected, before: c.frame.before, after: c.frame.after }
  SelfGraded _ -> Nothing
  Choice _ -> Nothing

choice :: Exercise -> Maybe { options :: Array String, expected :: String, before :: String, after :: String }
choice e = case e.answer of
  Choice c -> Just { options: NonEmpty.toArray c.options, expected: c.expected, before: c.frame.before, after: c.frame.after }
  _ -> Nothing

isChoice :: Answer -> Boolean
isChoice = case _ of
  Choice _ -> true
  _ -> false
