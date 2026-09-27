module Test.Flashcards.PersonShiftSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmpty
import Data.Maybe (Maybe(..), isNothing)
import Data.Set as Set
import Flashcards.Data.Paraphrase.Spanish (prompts)
import Flashcards.Data.Sentences.Spanish (sentences)
import Flashcards.Data.Verbs.Spanish (table)
import Flashcards.Exercise (Answer(..), Exercise, pools)
import Flashcards.Types.Card (Slug(..), slugToString)
import Flashcards.Verbs.Paraphrase as Paraphrase
import Flashcards.Verbs.PersonShift (exercise, exercises)
import Flashcards.Verbs.Shift (Sentence)
import Flashcards.Verbs.Shift as Shift
import Flashcards.Verbs.Table (Person(..), Tense(..))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

spec :: Spec Unit
spec = do
  describe "the person shift" do
    it "moves a sentence to the person it is asked for" do
      case exercise table tengo Pl1 of
        Nothing -> fail "no exercise"
        Just e -> do
          e.slug `shouldEqual` Slug "person.tener.present.1p"
          e.prompt `shouldEqual` "tengo mucho trabajo"
          e.hint `shouldEqual` "nosotros"
          frameOf e `shouldEqual` Just { before: "", after: " mucho trabajo" }
          expected e `shouldEqual` Just "tenemos"

    it "holds the tense still" do
      expected' fui Pl3 `shouldEqual` Just "fueron"
      (exercise table fui Pl3 <#> _.slug) `shouldEqual` Just (Slug "person.ir.preterite.3p")

    it "frames a verb in the middle of its sentence" do
      case exercise table puedo Sg2 of
        Nothing -> fail "no exercise"
        Just e -> do
          frameOf e `shouldEqual` Just { before: "no ", after: " dormir" }
          expected e `shouldEqual` Just "puedes"

    it "names every person by a pronoun" do
      map (\p -> exercise table tengo p <#> _.hint) [ Sg2, Sg3, Pl1, Pl3 ]
        `shouldEqual` map Just [ "tú", "él", "nosotros", "ellos" ]

    it "asks nothing of the person the sentence is already in" do
      isNothing (exercise table tengo Sg1) `shouldEqual` true

    -- `estoy muy enfermo` has no subject, and still cannot move: `enfermo`
    -- agrees with it, and `estamos muy enfermo` is not Spanish.
    it "nor of a sentence not marked as taking one" do
      isNothing (exercise table tengo { personShift = false } Pl1) `shouldEqual` true

    it "nor of a verb the table does not have" do
      isNothing (exercise table tengo { infinitive = "haber" } Pl1) `shouldEqual` true

  describe "the person-shift bank" do
    let yielded = exercises table sentences
        marked = Array.filter _.personShift sentences

    it "yields a question for every marked sentence in every person it is not in" do
      Array.length yielded `shouldEqual` (Array.length marked * 4)

    it "leaves out the sentences that are not marked" do
      (Array.length marked < Array.length sentences) `shouldEqual` true

    -- Which takes three source persons per verb and tense, not two: a
    -- sentence cannot be asked into its own person, so with two sentences
    -- the persons they are in each have a pool of one.
    it "has at least two sentences for every item" do
      pools yielded
        # Array.filter (\p -> NonEmpty.length p.exercises < 2)
        # map _.slug
        # shouldEqual []

    -- Over the same verbs and tenses, a person shift and a tense shift are
    -- different questions. One slug space would have each credit the other.
    it "shares no item with the tense shift" do
      let shifts = Set.fromFoldable $ map _.slug $ Shift.exercises table sentences
      Array.filter (\e -> Set.member e.slug shifts) yielded # map (slugToString <<< _.slug)
        # shouldEqual []

    it "nor with the paraphrase" do
      let paraphrases = Set.fromFoldable $ map _.slug $ Paraphrase.exercises prompts
      Array.filter (\e -> Set.member e.slug paraphrases) yielded # map (slugToString <<< _.slug)
        # shouldEqual []
  where
    tengo = sentence "" "tengo" " mucho trabajo" "tener" Present Sg1
    puedo = sentence "no " "puedo" " dormir" "poder" Present Sg1
    fui = sentence "" "fui" " a la playa" "ir" Preterite Sg1

    expected' s target = exercise table s target >>= expected

expected :: Exercise -> Maybe String
expected e = case e.answer of
  Checked c -> Just c.expected
  SelfGraded _ -> Nothing

frameOf :: Exercise -> Maybe { before :: String, after :: String }
frameOf e = case e.answer of
  Checked c -> Just c.frame
  SelfGraded _ -> Nothing

sentence :: String -> String -> String -> String -> Tense -> Person -> Sentence
sentence before form after infinitive tense person =
  { before, form, after, infinitive, tense, person, personShift: true }
