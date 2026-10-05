module Test.Flashcards.GridSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmpty
import Data.DateTime.Instant (Instant, instant)
import Data.Maybe (Maybe(..), fromJust)
import Data.String as String
import Data.Time.Duration (Milliseconds(..))
import Flashcards.Exercise (Answer(..), Drilled, Exercise, pools)
import Flashcards.Scheduler (maxBox)
import Flashcards.Types.Card (Slug(..), slugToString)
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress
import Flashcards.Verbs.Coverage (Recommend(..))
import Flashcards.Verbs.Curriculum (items)
import Flashcards.Verbs.Curriculum as Curriculum
import Flashcards.Verbs.Grid (State(..), VerbRow, grid)
import Flashcards.Verbs.Table (Person(..), Tense(..))
import Partial.Unsafe (unsafePartial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

now :: Instant
now = unsafePartial $ fromJust $ instant $ Milliseconds 0.0

persons :: Array Person
persons = [ Sg1, Sg2, Sg3, Pl1, Pl3 ]

-- | Two verbs and every cell of them, with forms nobody needs to read.
table :: Array { infinitive :: String, tense :: Tense, person :: Person, form :: String }
table = do
  infinitive <- [ "tener", "ser", "zzz" ]
  tense <- [ Present, Preterite, Imperfect, Subjunctive ]
  person <- persons
  pure { infinitive, tense, person, form: infinitive <> show tense <> show person }

ranks :: String -> Maybe Int
ranks = case _ of
  "ser" -> Just 1
  "tener" -> Just 2
  _ -> Nothing

ask :: String -> Maybe Drilled -> Exercise
ask slug cell =
  { slug: Slug slug, label: slug, family: "", cell, prompt: "", hint: ""
  , answer: Checked { expected: "", frame: { before: "", after: "" }, note: "" }
  }

at :: String -> Tense -> Person -> Maybe Drilled
at infinitive tense person = Just { infinitive, tense, person }

seen :: Int -> String -> Progress -> Progress
seen box slug = Progress.insert (Slug slug)
  { box, seen: 1, missed: 0, lapses: 0, due: now, direction: Recognition }

stateAt :: String -> Tense -> Array VerbRow -> Maybe State
stateAt infinitive tense rows = do
  row <- Array.find (\r -> r.infinitive == infinitive) rows
  _.state <$> Array.find (\s -> s.tense == tense) row.squares

spec :: Spec Unit
spec = describe "the conjugation grid" do
  let
    -- Every cell is drill unless a test says otherwise.
    coverage overrides = table <#> \c ->
      { infinitive: c.infinitive, tense: c.tense, person: c.person
      , recommend: case Array.find (\o -> o.infinitive == c.infinitive && o.tense == c.tense) overrides of
          Just o -> o.recommend c.person
          Nothing -> Drill
      }
    bank =
      -- A tense shift, asked in two persons.
      [ ask "tener.preterite" (at "tener" Preterite Sg1)
      , ask "tener.preterite" (at "tener" Preterite Pl3)
      -- Two of a person shift's five on one square.
      , ask "person.tener.present.1s" (at "tener" Present Sg1)
      , ask "person.tener.present.2s" (at "tener" Present Sg2)
      -- A correction, spanning two squares, one of which nothing else asks.
      , ask "error.boot" (at "tener" Present Pl1)
      , ask "error.boot" (at "ser" Imperfect Pl1)
      -- No cell at all.
      , ask "porpara.means" Nothing
      ]
    build progress overrides = grid ranks table (coverage overrides) (pools bank) progress

  it "orders the verbs by rank, and one it does not rank last" do
    map _.infinitive (build Progress.empty []) `shouldEqual` [ "ser", "tener", "zzz" ]

  it "has every tense for every verb, and every person's form in each" do
    map (map _.tense <<< _.squares) (build Progress.empty [])
      `shouldEqual` Array.replicate 3 [ Present, Preterite, Imperfect, Subjunctive ]
    map (map (Array.length <<< _.forms) <<< _.squares) (build Progress.empty [])
      `shouldEqual` Array.replicate 3 (Array.replicate 4 5)

  describe "a square nothing asks" do
    it "is left out when the coverage says skip for every person" do
      stateAt "ser" Subjunctive (build Progress.empty [ { infinitive: "ser", tense: Subjunctive, recommend: const Skip } ])
        `shouldEqual` Just LeftOut

    it "is not, when even one person is worth drilling" do
      let firstOnly = { infinitive: "ser", tense: Subjunctive, recommend: \p -> if p == Sg1 then Drill else Skip }
      stateAt "ser" Subjunctive (build Progress.empty [ firstOnly ]) `shouldEqual` Just Unasked

    it "counts later as worth drilling, since it is, only later" do
      stateAt "ser" Subjunctive (build Progress.empty [ { infinitive: "ser", tense: Subjunctive, recommend: const Later } ])
        `shouldEqual` Just Unasked

    it "is not left out for want of a verdict" do
      stateAt "ser" Present (grid ranks table [] (pools bank) Progress.empty) `shouldEqual` Just Unasked

  describe "a square something asks" do
    it "is ready before anything on it has been answered" do
      stateAt "tener" Preterite (build Progress.empty []) `shouldEqual` Just Ready

    it "is being learned once one item on it has" do
      stateAt "tener" Present (build (seen 1 "person.tener.present.1s" Progress.empty) [])
        `shouldEqual` Just Learning

    it "is known only once every item on it is mastered" do
      let one = seen maxBox "person.tener.present.1s" Progress.empty
      stateAt "tener" Present (build one []) `shouldEqual` Just Learning
      stateAt "tener" Present (build (seen maxBox "person.tener.present.2s" one) []) `shouldEqual` Just Known

    -- What the drills ask is what the drills ask, whatever the coverage
    -- would have recommended: hiding it would hide progress that is real.
    it "shows its progress even where the coverage says skip" do
      stateAt "tener" Preterite (build Progress.empty [ { infinitive: "tener", tense: Preterite, recommend: const Skip } ])
        `shouldEqual` Just Ready

  describe "an item spanning squares" do
    it "makes a square it alone reaches ready, since something does ask it" do
      stateAt "ser" Imperfect (build Progress.empty []) `shouldEqual` Just Ready

    it "but its progress is about the mistake, so it moves no square" do
      let mastered = seen maxBox "error.boot" Progress.empty
      stateAt "ser" Imperfect (build mastered []) `shouldEqual` Just Ready
      stateAt "tener" Present (build mastered []) `shouldEqual` Just Ready

  it "says what the coverage thinks of each form" do
    let
      rows = build Progress.empty [ { infinitive: "ser", tense: Present, recommend: \p -> if p == Sg1 then Drill else Skip } ]
      forms = Array.find (\r -> r.infinitive == "ser") rows >>= Array.head <<< _.squares <#> _.forms
    map (map _.recommend) forms `shouldEqual` Just [ Just Drill, Just Skip, Just Skip, Just Skip, Just Skip ]

  describe "the real one" do
    let rows = Curriculum.grid Progress.empty

    it "has all thirty-eight verbs, the most common first" do
      Array.length rows `shouldEqual` 38
      map _.infinitive (Array.take 3 rows) `shouldEqual` [ "querer", "poder", "tener" ]

    -- The case `Grid.grid` notes and does not design for: a square only a
    -- correction reaches, shaded ready while nothing on it can move. When a
    -- correction sentence reaches past the shifts, decide what that square
    -- should say, then change this.
    it "has no square that only an error correction reaches" do
      let
        exercises = Array.concatMap (NonEmpty.toArray <<< _.exercises) items
        squareOf e = e.cell <#> \c -> { infinitive: c.infinitive, tense: c.tense }
        correction e = String.take 6 (slugToString e.slug) == "error."
        shifted = Array.nub $ Array.mapMaybe squareOf $ Array.filter (not <<< correction) exercises
        corrected = Array.nub $ Array.mapMaybe squareOf $ Array.filter correction exercises
      Array.filter (\s -> not (Array.elem s shifted)) corrected `shouldEqual` []
      (Array.length corrected > 0) `shouldEqual` true

    it "shows nothing as known or being learned before anything is answered" do
      Array.filter (\s -> s.state == Known || s.state == Learning) (Array.concatMap _.squares rows)
        # map (\s -> s.infinitive <> " " <> show s.tense)
        # shouldEqual []
