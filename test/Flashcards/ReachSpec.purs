module Test.Flashcards.ReachSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.String as String
import Flashcards.Data.Coverage.Spanish (coverage)
import Flashcards.Exercise (Answer(..), Drilled, Exercise)
import Flashcards.Types.Card (Slug(..))
import Flashcards.Verbs.Coverage (Recommend(..), Verdict)
import Flashcards.Verbs.Curriculum (corrected, mooded, produced)
import Flashcards.Verbs.Reach (reach, reachedBy, render, unreached)
import Flashcards.Verbs.Table (Person(..), Tense(..))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)

verdict :: String -> Tense -> Person -> Recommend -> Verdict
verdict infinitive tense person recommend = { infinitive, tense, person, recommend }

ask :: Maybe Drilled -> Exercise
ask cell =
  { slug: Slug "x", label: "x", family: "", cell, prompt: "", hint: ""
  , answer: Checked { expected: "", frame: { before: "", after: "" }, note: "" }
  }

at :: String -> Tense -> Person -> Maybe Drilled
at infinitive tense person = Just { infinitive, tense, person }

verdicts :: Array Verdict
verdicts =
  [ verdict "ser" Present Sg1 Drill
  , verdict "ser" Present Sg2 Drill
  , verdict "ser" Preterite Sg1 Drill
  , verdict "ser" Subjunctive Sg1 Drill
  , verdict "ser" Imperfect Sg1 Later
  , verdict "ser" Imperfect Sg2 Skip
  ]

spec :: Spec Unit
spec = describe "Reach" do
  let
    r = reach verdicts
      { produced: [ ask (at "ser" Present Sg1), ask Nothing, ask (at "ser" Imperfect Sg1) ]
      , mood: []
      , corrected: [ ask (at "ser" Present Sg2) ]
      }

  describe "what it counts" do
    it "takes the drill cells outside the subjunctive as the denominator" do
      Array.length r.denominator `shouldEqual` 3

    it "says how many subjunctive drill cells it left out" do
      r.subjunctive `shouldEqual` 1

    it "keeps `later` cells out of the denominator, and reaching one changes nothing" do
      Array.length r.later `shouldEqual` 1
      Array.length (reachedBy { countCorrection: true } r) `shouldEqual` 2

    it "ignores an exercise with no cell" do
      Array.length (reachedBy { countCorrection: false } r) `shouldEqual` 1

  -- #230. A verb the trigger frames cover has its subjunctive in the
  -- denominator, and the frames' cells count as reached.
  describe "a verb the trigger frames cover" do
    let
      covered = reach verdicts
        { produced: [ ask (at "ser" Present Sg1) ]
        , mood: [ (ask (at "ser" Subjunctive Sg1)) { family = "ser" } ]
        , corrected: []
        }

    it "brings its subjunctive drill cells into the denominator" do
      Array.length covered.denominator `shouldEqual` 4
      covered.subjunctive `shouldEqual` 0

    it "counts the cell a frame asks as reached, by a drill that has you produce it" do
      Array.length (reachedBy { countCorrection: false } covered) `shouldEqual` 2

    it "leaves another verb's subjunctive out" do
      let other = reach (verdicts <> [ verdict "tener" Subjunctive Sg1 Drill ])
            { produced: [], mood: [ (ask (at "ser" Subjunctive Sg1)) { family = "ser" } ], corrected: [] }
      other.subjunctive `shouldEqual` 1

  describe "error correction" do
    it "counts only when asked to" do
      unreached { countCorrection: false } r `shouldEqual`
        [ { infinitive: "ser", tense: Present, person: Sg2 }
        , { infinitive: "ser", tense: Preterite, person: Sg1 }
        ]
      unreached { countCorrection: true } r `shouldEqual`
        [ { infinitive: "ser", tense: Preterite, person: Sg1 } ]

  describe "the report" do
    it "states its denominator and what it excludes" do
      let out = render r
      out `shouldSatisfy` String.contains (String.Pattern "Denominator: 3 cells")
      out `shouldSatisfy` String.contains (String.Pattern "Excluded: 1 subjunctive")
      out `shouldSatisfy` String.contains (String.Pattern "trigger frames cover")

  describe "the real curriculum" do
    let real = reach coverage { produced, mood: mooded, corrected }

    it "has the denominator #114 counted" do
      Array.length real.denominator `shouldEqual` 383

    -- A floor and not a figure: #104 adds sentences, and each one can only
    -- raise this. It falls when a sentence is dropped or a generator comes to
    -- skip more, which is what it is here to notice.
    it "does not reach fewer cells than it did" do
      Array.length (reachedBy { countCorrection: true } real) `shouldSatisfy` (_ >= 314)
