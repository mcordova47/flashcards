module Test.Flashcards.MoodSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmpty
import Data.Foldable (for_)
import Data.Maybe (Maybe(..), isNothing)
import Data.Set as Set
import Data.String as String
import Flashcards.Data.Coverage.Spanish (coverage)
import Flashcards.Data.Triggers.Spanish (triggers)
import Flashcards.Data.Verbs.Spanish (table)
import Flashcards.Exercise (Answer(..), Exercise, Verdict(..), matches, pick, pools)
import Flashcards.Types.Card (Slug(..), slugToString)
import Flashcards.Types.Progress (CardProgress)
import Flashcards.Types.Direction (Direction(..))
import Partial.Unsafe (unsafePartial)
import Partial (crashWith)
import Flashcards.Verbs.Coverage (Recommend(..))
import Flashcards.Verbs.Curriculum (kind, mooded, moodVerbs)
import Flashcards.Verbs.Mood (Group(..), Mood(..), Trigger, exercise, exercises, interleave, tense)
import Flashcards.Verbs.Table (Person(..), formOf)
import Flashcards.Verbs.Table as Table
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual, shouldSatisfy)

wants :: Trigger
wants =
  { trigger: "mi madre quiere que", mood: Subjunctive, group: Wish
  , reason: "wanting something of someone takes the subjunctive"
  }

believes :: Trigger
believes =
  { trigger: "mi madre cree que", mood: Indicative, group: Certainty
  , reason: "believing something takes the indicative"
  }

persons :: Array Person
persons = [ Sg1, Sg2, Sg3, Pl1, Pl3 ]

spec :: Spec Unit
spec = describe "the trigger frame" do
  describe "an exercise" do
    it "puts the pronoun after the trigger and asks the infinitive alone" do
      case exercise table "tener" Sg2 wants of
        Nothing -> fail "no exercise"
        Just e -> do
          e.slug `shouldEqual` Slug "mood.tener.2s"
          e.hint `shouldEqual` "tener"
          e.family `shouldEqual` "tener"
          case e.answer of
            Checked { frame, note } -> do
              frame `shouldEqual` { before: "mi madre quiere que tú ", after: "" }
              note `shouldEqual` "wish or request · wanting something of someone takes the subjunctive"
            _ -> fail "not checked"

    -- The form is the table's. Typed from memory of the rule it would be
    -- `tenga`, which is also what the table has, so the second half is the
    -- one that says anything: an irregular verb is where a rule would err.
    it "expects the table's subjunctive after a subjunctive trigger" do
      expected (exercise table "tener" Sg2 wants) `shouldEqual` Just "tengas"
      expected (exercise table "ir" Pl3 wants) `shouldEqual` Just "vayan"
      expected (exercise table "ser" Sg1 wants) `shouldEqual` Just "sea"

    it "and the table's present after an indicative one" do
      expected (exercise table "tener" Sg2 believes) `shouldEqual` Just "tienes"
      expected (exercise table "ir" Pl3 believes) `shouldEqual` Just "van"

    it "names the cell the form came from" do
      (exercise table "tener" Sg2 wants <#> _.cell) `shouldEqual` Just (Just { infinitive: "tener", tense: Table.Subjunctive, person: Sg2 })
      (exercise table "tener" Sg2 believes <#> _.cell) `shouldEqual` Just (Just { infinitive: "tener", tense: Table.Present, person: Sg2 })

    it "grades the wrong mood as wrong: `vienen` for `vengan`" do
      matches "vengan" "vienen" `shouldEqual` Wrong
      matches "vengan" "vengan" `shouldEqual` Exact

    it "asks nothing of a verb the table does not have" do
      isNothing (exercise table "ennegrecer" Sg1 wants) `shouldEqual` true

    it "refuses a trigger with no reason" do
      isNothing (exercise table "tener" Sg1 wants { reason = "" }) `shouldEqual` true
      isNothing (exercise table "tener" Sg1 wants { reason = "  " }) `shouldEqual` true

  -- The research found 0 of 190 subjunctive cells equal to the present, and
  -- the frame's whole premise is that the form typed shows the mood chosen.
  -- Accents are forgiven in grading, so it has to hold without them too.
  describe "every cell the bank wires" do
    it "has a subjunctive that differs from its present, accents or not" do
      for_ moodVerbs \verb -> for_ persons \p ->
        case formOf verb Table.Present p table, formOf verb Table.Subjunctive p table of
          Just present, Just subj -> do
            (present == subj) `shouldEqual` false
            matches subj present `shouldEqual` Wrong
          _, _ -> fail (verb <> " is missing a cell")

    it "is read from the table, never made" do
      for_ mooded \e -> case e.answer, e.cell of
        Checked { expected: x }, Just c -> formOf c.infinitive c.tense c.person table `shouldEqual` Just x
        _, _ -> fail "an exercise without a cell"

    it "has the cell its mood calls for: subjunctive or present, and no other" do
      for_ mooded \e -> case e.cell of
        Just c -> (c.tense == Table.Subjunctive || c.tense == Table.Present) `shouldEqual` true
        Nothing -> fail "no cell"

  describe "the verbs" do
    it "are nine, the most common whose whole subjunctive the coverage says drill" do
      moodVerbs `shouldEqual`
        [ "querer", "poder", "tener", "ver", "ir", "decir", "venir", "ser", "estar" ]

    it "leave out a verb with a skipped person, which the ending rule gives" do
      (Array.elem "dar" moodVerbs) `shouldEqual` false
      Array.length (Array.filter (\v -> v.infinitive == "dar" && v.tense == Table.Subjunctive && v.recommend == Skip) coverage) `shouldSatisfy` (_ > 0)

  describe "an item" do
    let pooled = pools mooded

    it "is a verb and a person, with the whole bank as its pool" do
      Array.length pooled `shouldEqual` (Array.length moodVerbs * 5)
      for_ pooled \p -> NonEmpty.length p.exercises `shouldEqual` Array.length triggers

    it "is on one cell's subjunctive and its present, and no other person" do
      for_ pooled \p ->
        Set.size (Set.fromFoldable (map _.person (Array.mapMaybe _.cell (NonEmpty.toArray p.exercises)))) `shouldEqual` 1

    it "turns through every trigger before it repeats one" do
      let pool = pool' "tener" Sg2
      let asked = map ask (Array.range 0 (Array.length triggers - 1))
          ask n = frameBefore (pick (Just (seen n)) pool)
      Array.length (Array.nub asked) `shouldEqual` Array.length triggers

    it "has the same verb and person met with different triggers" do
      let a = frameBefore (pick Nothing (pool' "tener" Sg2))
          b = frameBefore (pick (Just (seen 1)) (pool' "tener" Sg2))
      (a /= b) `shouldEqual` true

    it "does not start every pool on the same trigger" do
      let firsts = map (\p -> frameBefore (pick Nothing p)) pooled
      (Array.length (Array.nub firsts) > 5) `shouldEqual` true

    it "has an indicative trigger among every ten sightings" do
      for_ pooled \p ->
        for_ (Array.range 0 (NonEmpty.length p.exercises - 10)) \start ->
          let window = map (\n -> pick (Just (seen n)) p) (Array.range start (start + 9))
          in Array.any (\e -> map _.tense e.cell == Just Table.Present) window `shouldEqual` true

  describe "the curriculum" do
    it "knows an item of the bank as its own kind, so that a session takes it across kinds" do
      for_ (pools mooded) \p -> kind p.slug `shouldEqual` "mood"

  describe "interleaving the groups" do
    it "takes one of each group in turn" do
      map _.group (Array.take 7 (interleave triggers))
        `shouldEqual` [ Wish, Doubt, Emotion, Judgment, PurposeTime, Certainty, Fact ]

    it "keeps every trigger and adds none" do
      Array.sort (map _.trigger (interleave triggers)) `shouldEqual` Array.sort (map _.trigger triggers)

  describe "the bank" do
    it "asks the indicative a real share of the time, so that the subjunctive is not a given" do
      let n = Array.length (Array.filter (\t -> t.mood == Indicative) triggers)
      (4 * n >= Array.length triggers) `shouldEqual` true

    it "answers each trigger by the mood its group has" do
      for_ triggers \t -> tense t.mood `shouldEqual` (if t.mood == Indicative then Table.Present else Table.Subjunctive)
  where
    expected = (_ >>= \e -> case e.answer of
      Checked { expected: x } -> Just x
      _ -> Nothing)
    pool' verb p = case Array.find (\q -> q.slug == Slug ("mood." <> verb <> "." <> code p)) (pools mooded) of
      Just q -> q
      Nothing -> unsafePartial (crashWith "no pool")
    frameBefore e = case e.answer of
      Checked { frame } -> frame.before
      _ -> ""
    seen n = { box: 1, due: bottom, seen: n, lapses: 0, missed: 0, direction: Recognition } :: CardProgress
    code = case _ of
      Sg1 -> "1s"
      Sg2 -> "2s"
      Sg3 -> "3s"
      Pl1 -> "1p"
      Pl3 -> "3p"
