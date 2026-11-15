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
import Flashcards.Data.Triggers.Spanish (sentences)
import Flashcards.Data.Verbs.Spanish (table)
import Flashcards.Exercise (Answer(..), Exercise, Verdict(..), matches, pick, pools)
import Flashcards.Types.Card (Slug(..), slugToString)
import Flashcards.Types.Progress (CardProgress)
import Flashcards.Types.Direction (Direction(..))
import Partial.Unsafe (unsafePartial)
import Partial (crashWith)
import Flashcards.Verbs.Coverage (Recommend(..))
import Flashcards.Verbs.Curriculum (kind, mooded, moodVerbs)
import Flashcards.Verbs.Mood (Group(..), Mood(..), Sentence, exercise, exercises, interleave, tense)
import Flashcards.Verbs.Table (Person(..), formOf)
import Flashcards.Verbs.Table as Table
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual, shouldSatisfy)

wants :: Sentence
wants =
  { trigger: "querer que", mood: Subjunctive, group: Wish
  , reason: "wanting something of someone takes the subjunctive"
  , verb: "tener", person: Sg2
  , before: "mi madre quiere que tú ", after: " mucho cuidado"
  }

believes :: Sentence
believes =
  { trigger: "creer que", mood: Indicative, group: Certainty
  , reason: "believing something takes the indicative"
  , verb: "tener", person: Sg2
  , before: "mi madre cree que tú ", after: " mucho cuidado"
  }

persons :: Array Person
persons = [ Sg1, Sg2, Sg3, Pl1, Pl3 ]

spec :: Spec Unit
spec = describe "the trigger frame" do
  describe "an exercise" do
    it "gives the sentence either side of the blank and asks the infinitive alone" do
      case exercise table wants of
        Nothing -> fail "no exercise"
        Just e -> do
          e.slug `shouldEqual` Slug "mood.tener.2s"
          e.hint `shouldEqual` "tener"
          e.family `shouldEqual` "tener"
          case e.answer of
            Checked { frame, note } -> do
              frame `shouldEqual` { before: "mi madre quiere que tú ", after: " mucho cuidado" }
              note `shouldEqual` "wish or request · wanting something of someone takes the subjunctive"
            _ -> fail "not checked"

    -- The form is the table's. Typed from memory of the rule it would be
    -- `tenga`, which is also what the table has, so the second half is the
    -- one that says anything: an irregular verb is where a rule would err.
    it "expects the table's subjunctive after a subjunctive trigger" do
      expected (exercise table wants) `shouldEqual` Just "tengas"
      expected (exercise table wants { verb = "ir", person = Pl3 }) `shouldEqual` Just "vayan"
      expected (exercise table wants { verb = "ser", person = Sg1 }) `shouldEqual` Just "sea"

    it "and the table's present after an indicative one" do
      expected (exercise table believes) `shouldEqual` Just "tienes"
      expected (exercise table believes { verb = "ir", person = Pl3 }) `shouldEqual` Just "van"

    it "names the cell the form came from" do
      (exercise table wants <#> _.cell) `shouldEqual` Just (Just { infinitive: "tener", tense: Table.Subjunctive, person: Sg2 })
      (exercise table believes <#> _.cell) `shouldEqual` Just (Just { infinitive: "tener", tense: Table.Present, person: Sg2 })

    it "grades the wrong mood as wrong: `vienen` for `vengan`" do
      matches "vengan" "vienen" `shouldEqual` Wrong
      matches "vengan" "vengan" `shouldEqual` Exact

    it "asks nothing of a verb the table does not have" do
      isNothing (exercise table wants { verb = "ennegrecer" }) `shouldEqual` true

    it "refuses a sentence with no reason" do
      isNothing (exercise table wants { reason = "" }) `shouldEqual` true
      isNothing (exercise table wants { reason = "  " }) `shouldEqual` true

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
        sentencesOf verb person = Array.filter (\s -> s.verb == verb && s.person == person) sentences

    it "is a verb and a person, with the sentences written for it as its pool" do
      Array.length pooled `shouldEqual` (Array.length moodVerbs * 5)
      for_ moodVerbs \verb -> for_ persons \p ->
        NonEmpty.length (pool' verb p).exercises `shouldEqual` Array.length (sentencesOf verb p)

    -- #241 changed what an item asks and not what it is, so that what a
    -- learner has done under these ids (their box, due date, misses) carries
    -- over. The 45 are spelled out, as #230 made them.
    it "keeps the 45 ids the trigger frames had" do
      Array.sort (map (_.slug >>> slugToString) pooled) `shouldEqual` Array.sort
        (Array.concatMap (\v -> map (\c -> "mood." <> v <> "." <> c) [ "1s", "2s", "3s", "1p", "3p" ])
          [ "querer", "poder", "tener", "ver", "ir", "decir", "venir", "ser", "estar" ])

    it "has several sentences for every verb and person it wires, so that a pool turns" do
      for_ pooled \p -> (NonEmpty.length p.exercises >= 4) `shouldEqual` true

    it "is on one cell's subjunctive and its present, and no other person" do
      for_ pooled \p ->
        Set.size (Set.fromFoldable (map _.person (Array.mapMaybe _.cell (NonEmpty.toArray p.exercises)))) `shouldEqual` 1

    it "has sentences only for the verbs it wires, so that none is written and never asked" do
      for_ sentences \s -> Array.elem s.verb moodVerbs `shouldEqual` true

    it "turns through every sentence before it repeats one" do
      let pool = pool' "tener" Sg2
          n = NonEmpty.length pool.exercises
          asked = map ask (Array.range 0 (n - 1))
          ask k = sentenceOf (pick (Just (seen k)) pool)
      Array.length (Array.nub asked) `shouldEqual` n

    it "has the same verb and person met with different sentences" do
      let a = sentenceOf (pick Nothing (pool' "tener" Sg2))
          b = sentenceOf (pick (Just (seen 1)) (pool' "tener" Sg2))
      (a /= b) `shouldEqual` true

    it "does not start every pool on the same sentence" do
      let firsts = map (\p -> sentenceOf (pick Nothing p)) pooled
      (Array.length (Array.nub firsts) > 20) `shouldEqual` true

    it "has an indicative sentence among every pool's four sightings, and a subjunctive one" do
      for_ pooled \p ->
        for_ (Array.range 0 (NonEmpty.length p.exercises - 4)) \start ->
          let window = map (\n -> pick (Just (seen n)) p) (Array.range start (start + 3))
          in do
            Array.any (\e -> map _.tense e.cell == Just Table.Present) window `shouldEqual` true
            Array.any (\e -> map _.tense e.cell == Just Table.Subjunctive) window `shouldEqual` true

  describe "the curriculum" do
    it "knows an item of the bank as its own kind, so that a session takes it across kinds" do
      for_ (pools mooded) \p -> kind p.slug `shouldEqual` "mood"

  describe "interleaving the groups" do
    it "takes one of each group in turn" do
      map _.group (Array.take 4 (interleave
        [ wants, wants { group = Doubt }, wants { group = Doubt }, believes ]))
        `shouldEqual` [ Wish, Doubt, Certainty, Doubt ]

    it "keeps every sentence and adds none" do
      Array.sort (map _.before (interleave sentences)) `shouldEqual` Array.sort (map _.before sentences)

  describe "the bank" do
    it "asks the indicative a real share of the time, so that the subjunctive is not a given" do
      let n = Array.length (Array.filter (\t -> t.mood == Indicative) sentences)
      (4 * n >= Array.length sentences) `shouldEqual` true

    it "has every kind of meaning" do
      for_ [ Wish, Doubt, Emotion, Judgment, PurposeTime, Certainty, Fact ] \g ->
        Array.any (\s -> s.group == g) sentences `shouldEqual` true

    it "answers each sentence by the mood its trigger has" do
      for_ sentences \t -> tense t.mood `shouldEqual` (if t.mood == Indicative then Table.Present else Table.Subjunctive)

    it "has no blank without a subject before it, and no blank at the start" do
      for_ sentences \s -> (String.length s.before > 3 && String.take 1 s.before /= " ") `shouldEqual` true

    it "has a table cell for every sentence, in the mood its trigger calls for" do
      for_ sentences \s -> isNothing (exercise table s) `shouldEqual` false
  where
    expected = (_ >>= \e -> case e.answer of
      Checked { expected: x } -> Just x
      _ -> Nothing)
    pool' verb p = case Array.find (\q -> q.slug == Slug ("mood." <> verb <> "." <> code p)) (pools mooded) of
      Just q -> q
      Nothing -> unsafePartial (crashWith "no pool")
    sentenceOf e = case e.answer of
      Checked { frame } -> frame.before <> frame.after
      _ -> ""
    seen n = { box: 1, due: bottom, seen: n, lapses: 0, missed: 0, direction: Recognition } :: CardProgress
    code = case _ of
      Sg1 -> "1s"
      Sg2 -> "2s"
      Sg3 -> "3s"
      Pl1 -> "1p"
      Pl3 -> "3p"
