module Test.Flashcards.ShiftSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmpty
import Data.Maybe (Maybe(..), isNothing)
import Flashcards.Data.Sentences.Spanish (sentences)
import Flashcards.Data.Verbs.Spanish (table)
import Flashcards.Exercise (Answer(..), Exercise, pools)
import Flashcards.Types.Card (Slug(..))
import Flashcards.Verbs.Shift (Sentence, exercise, exercises)
import Flashcards.Verbs.Table (Person(..), Tense(..), formOf)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

spec :: Spec Unit
spec = do
  describe "the tense shift" do
    it "moves a sentence to the tense it is asked for" do
      case exercise table tengo Preterite of
        Nothing -> fail "no exercise"
        Just e -> do
          e.slug `shouldEqual` Slug "tener.preterite"
          e.prompt `shouldEqual` "tengo mucho trabajo"
          e.hint `shouldEqual` "preterite"
          e.frame `shouldEqual` { before: "", after: " mucho trabajo" }
          expected e `shouldEqual` Just "tuve"

    it "takes the form from the table, accent and all" do
      expected' tengo Imperfect `shouldEqual` Just "tenía"

    it "frames a verb in the middle of its sentence" do
      case exercise table puedo Preterite of
        Nothing -> fail "no exercise"
        Just e -> do
          e.frame `shouldEqual` { before: "no ", after: " dormir" }
          expected e `shouldEqual` Just "pude"

    it "and one that is not in the present to start with" do
      expected' fui Present `shouldEqual` Just "voy"
      expected' fui Imperfect `shouldEqual` Just "iba"

    it "asks nothing of the tense the sentence is already in" do
      isNothing (exercise table tengo Present) `shouldEqual` true

    -- A mood, not a tense: there is no reading of `tenga mucho trabajo` that is
    -- the same sentence at another time.
    it "nor of the subjunctive" do
      isNothing (exercise table tengo Subjunctive) `shouldEqual` true

    it "nor of a verb the table does not have" do
      isNothing (exercise table tengo { infinitive = "haber" } Preterite) `shouldEqual` true

  describe "the sentence bank" do
    let yielded = exercises table sentences

    -- A sentence that disagrees with the table would still render, and ask a
    -- question whose premise is wrong. tools/check-sentences.mjs says where.
    it "agrees with the table about every verb in it" do
      Array.filter (\s -> formOf s.infinitive s.tense s.person table /= Just s.form) sentences
        # map (\s -> s.before <> "[" <> s.form <> "]" <> s.after)
        # shouldEqual []

    it "yields a question for every sentence in every tense it is not in" do
      Array.length yielded `shouldEqual` (Array.length sentences * 2)

    -- Or a later sighting would ask the same sentence again, and the item
    -- could be passed by remembering one string.
    it "has at least two sentences for every item" do
      pools yielded
        # Array.filter (\p -> NonEmpty.length p.exercises < 2)
        # map _.slug
        # shouldEqual []
  where
    tengo = sentence "" "tengo" " mucho trabajo" "tener" Present Sg1
    puedo = sentence "no " "puedo" " dormir" "poder" Present Sg1
    fui = sentence "" "fui" " a la playa" "ir" Preterite Sg1

    expected' s target = exercise table s target >>= expected

expected :: Exercise -> Maybe String
expected e = case e.answer of
  Checked form -> Just form
  SelfGraded _ -> Nothing

sentence :: String -> String -> String -> String -> Tense -> Person -> Sentence
sentence before form after infinitive tense person =
  { before, form, after, infinitive, tense, person }
