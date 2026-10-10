module Test.Flashcards.CorrectionSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Array.NonEmpty as NonEmpty
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.Set as Set
import Data.String as String
import Data.Tuple (Tuple(..))
import Flashcards.Data.Paraphrase.Spanish (prompts)
import Flashcards.Data.Sentences.Spanish (sentences)
import Flashcards.Data.Verbs.Spanish (deviations, table)
import Flashcards.Exercise (Answer(..), Verdict(..), matches, pools)
import Flashcards.Types.Card (Slug(..), slugToString)
import Flashcards.Verbs.Correction (Kind(..), exercise, exercises, kinds, mistake)
import Flashcards.Verbs.Paraphrase as Paraphrase
import Flashcards.Verbs.PersonShift as PersonShift
import Flashcards.Verbs.Shift (Sentence)
import Flashcards.Verbs.Shift as Shift
import Flashcards.Verbs.Table (Person(..), Tense(..))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

spec :: Spec Unit
spec = do
  describe "making a mistake" do
    let wrong = mistake table deviations

    -- Exactly what `check-verbs` prints as "(not X)", because it is
    -- generated from the same list.
    it "regularises an irregular" do
      wrong Regularised "tener" Preterite Sg1 `shouldEqual` Just "tení"
      wrong Regularised "tener" Present Sg1 `shouldEqual` Just "teno"
      wrong Regularised "saber" Present Sg1 `shouldEqual` Just "sabo"
      wrong Regularised "poner" Preterite Sg2 `shouldEqual` Just "poniste"

    -- Exactly the regular form too, but the verb is regular in sound, and
    -- the rule is a spelling one. See #41.
    it "leaves a consonant unrespelt before -é" do
      wrong Orthographic "empezar" Preterite Sg1 `shouldEqual` Just "empezé"
      wrong Orthographic "llegar" Preterite Sg1 `shouldEqual` Just "llegé"
      wrong Orthographic "buscar" Preterite Sg1 `shouldEqual` Just "buscé"
      wrong Orthographic "jugar" Preterite Sg1 `shouldEqual` Just "jugé"
      wrong Regularised "empezar" Preterite Sg1 `shouldEqual` Nothing

    it "only where the respelling is" do
      wrong Orthographic "empezar" Preterite Sg2 `shouldEqual` Nothing
      wrong Orthographic "jugar" Present Sg1 `shouldEqual` Nothing
      wrong Regularised "jugar" Present Sg2 `shouldEqual` Just "jugas"

    -- #26 listed this as a stem change that did not happen, and it is the
    -- regular form; but its rule is its own. See #41.
    it "leaves an -ir preterite's stem open" do
      wrong StemIr "dormir" Preterite Sg3 `shouldEqual` Just "dormió"
      wrong StemIr "dormir" Preterite Pl3 `shouldEqual` Just "dormieron"
      wrong StemIr "sentir" Preterite Sg3 `shouldEqual` Just "sentió"
      wrong StemIr "pedir" Preterite Pl3 `shouldEqual` Just "pedieron"
      wrong StemIr "seguir" Preterite Sg3 `shouldEqual` Just "seguió"
      wrong Regularised "dormir" Preterite Sg3 `shouldEqual` Nothing

    -- `pedo` closes its stem too, but in the present, where the rule is the
    -- boot's; and `oyó`'s `y` is a spelling, not a stem.
    it "only in the preterite, and only of a vowel" do
      wrong StemIr "pedir" Present Sg1 `shouldEqual` Nothing
      wrong Regularised "pedir" Present Sg1 `shouldEqual` Just "pedo"
      wrong StemIr "dormir" Preterite Sg1 `shouldEqual` Nothing
      wrong StemIr "oír" Preterite Sg3 `shouldEqual` Nothing
      wrong StemIr "construir" Preterite Sg3 `shouldEqual` Nothing
      wrong StemIr "decir" Preterite Sg3 `shouldEqual` Nothing

    -- A vowel closed, one each, but by the strong stem, not by the rule.
    it "nor of a strong preterite, which closes vowels of its own" do
      wrong StemIr "poder" Preterite Sg2 `shouldEqual` Nothing
      wrong StemIr "venir" Preterite Pl3 `shouldEqual` Nothing
      wrong StemIr "dar" Preterite Sg1 `shouldEqual` Nothing
      wrong Regularised "venir" Preterite Pl3 `shouldEqual` Just "venieron"

    -- The three are one regular form split three ways, so a cell that is
    -- one is never another, and no error is asked under two items.
    it "files every regular form under one kind" do
      let
        regulars = [ Regularised, Orthographic, StemIr ]
        twice = do
          d <- deviations
          let made = Array.filter (\k -> isJust (wrong k d.infinitive d.tense d.person)) regulars
          if Array.length made > 1 then [ d.infinitive <> " " <> show d.tense <> " " <> show d.person ] else []
      twice `shouldEqual` []

    it "puts a preterite stem in the imperfect" do
      wrong StrongImperfect "tener" Imperfect Sg1 `shouldEqual` Just "tuvía"
      wrong StrongImperfect "hacer" Imperfect Pl1 `shouldEqual` Just "hicíamos"
      wrong StrongImperfect "tener" Preterite Sg1 `shouldEqual` Nothing

    it "gives a preterite stem the regular endings" do
      wrong StrongWeak "tener" Preterite Sg1 `shouldEqual` Just "tuví"
      wrong StrongWeak "tener" Preterite Sg3 `shouldEqual` Just "tuvió"
      wrong StrongWeak "decir" Preterite Pl3 `shouldEqual` Just "dijieron"

    it "carries a stem change into nosotros" do
      wrong Boot "tener" Present Pl1 `shouldEqual` Just "tienemos"
      wrong Boot "pensar" Present Pl1 `shouldEqual` Just "piensamos"
      wrong Boot "decir" Present Pl1 `shouldEqual` Just "dicimos"
      wrong Boot "tener" Present Sg1 `shouldEqual` Nothing

    it "only of a verb that has a stem change to carry" do
      wrong Boot "hacer" Present Pl1 `shouldEqual` Nothing

    it "only of a verb with a strong preterite" do
      wrong StrongWeak "pedir" Preterite Sg1 `shouldEqual` Nothing
      wrong StrongImperfect "dar" Imperfect Sg1 `shouldEqual` Nothing

    -- The one that matters most. `matches` forgives a missing accent, so
    -- this error typed back unchanged would be graded right.
    it "refuses a mistake that is only an accent" do
      wrong Regularised "estar" Present Sg2 `shouldEqual` Nothing
      wrong Regularised "oír" Preterite Sg2 `shouldEqual` Nothing

    it "refuses one that is the fix itself" do
      wrong StrongWeak "tener" Preterite Sg2 `shouldEqual` Nothing
      wrong StrongWeak "tener" Preterite Pl3 `shouldEqual` Nothing

    -- `estamos en casa` is good Spanish; mending it into the preterite is a
    -- tense shift, not a correction.
    it "refuses one that is the verb's form in another tense" do
      wrong Regularised "estar" Preterite Pl1 `shouldEqual` Nothing
      wrong Regularised "decir" Preterite Pl1 `shouldEqual` Nothing

    it "makes none of ser or ir" do
      wrong Regularised "ir" Present Sg1 `shouldEqual` Nothing
      wrong Regularised "ser" Imperfect Sg1 `shouldEqual` Nothing
      wrong StrongImperfect "ir" Imperfect Sg1 `shouldEqual` Nothing

    it "nor in the subjunctive, which no sentence can be in" do
      wrong Regularised "tener" Subjunctive Sg1 `shouldEqual` Nothing

    it "nor of a verb the table does not have" do
      wrong Regularised "haber" Present Sg3 `shouldEqual` Nothing

    -- Planted: the same table with tener's preterite taken off the
    -- deviations. Every kind is built from what check-verbs reports, so a
    -- cell it calls regular yields nothing.
    it "makes nothing of a cell check-verbs does not report" do
      let
        regularPreterite d = d.infinitive == "tener" && d.tense == Preterite
        without = Array.filter (not <<< regularPreterite) deviations
      mistake table without Regularised "tener" Preterite Sg1 `shouldEqual` Nothing
      mistake table without StrongWeak "tener" Preterite Sg1 `shouldEqual` Nothing
      mistake table without StrongImperfect "tener" Imperfect Sg1 `shouldEqual` Nothing

  describe "an error-correction exercise" do
    it "names a respelling" do
      case exercise table deviations empiezo Orthographic Preterite of
        Nothing -> fail "no exercise"
        Just e -> do
          e.slug `shouldEqual` Slug "error.orthographic"
          e.prompt `shouldEqual` "yo empezé a trabajar"
          expectedOf e `shouldEqual` "empecé"
          noteOf e `shouldEqual` "before -é, z is written c, to keep the sound"

    it "and an -ir stem closed" do
      case exercise table deviations duerme StemIr Preterite of
        Nothing -> fail "no exercise"
        Just e -> do
          e.slug `shouldEqual` Slug "error.stem-ir"
          e.prompt `shouldEqual` "el niño dormió en su cama"
          expectedOf e `shouldEqual` "durmió"
          noteOf e `shouldEqual` "an -ir verb that changes its stem closes it in the preterite's third persons: o to u"

    -- The note is of the cell and not the kind (#120). `hizo` once showed
    -- "and -eron after j", which has nothing to do with it.
    describe "the note says only what is true of the cell" do
      let noteFor s kind tense = exercise table deviations s kind tense <#> noteOf

      it "leaves j out of a strong preterite that has none" do
        noteFor hace StrongWeak Preterite
          `shouldEqual` Just "an irregular preterite stem takes -e and -o, which are not stressed"
        noteFor tengo StrongWeak Preterite
          `shouldEqual` Just "an irregular preterite stem takes -e and -o, which are not stressed"

      it "names j for the stem that has one" do
        noteFor dicen3 StrongWeak Preterite
          `shouldEqual` Just "a preterite stem ending in j takes -eron, not -ieron"

      it "says the one respelling a verb needs" do
        noteFor llego Orthographic Preterite
          `shouldEqual` Just "before -é, g is written gu, to keep the sound"
        noteFor busco Orthographic Preterite
          `shouldEqual` Just "before -é, c is written qu, to keep the sound"

      it "says the one vowel an -ir stem closes" do
        noteFor pide StemIr Preterite
          `shouldEqual` Just "an -ir verb that changes its stem closes it in the preterite's third persons: e to i"

    it "asks the sentence broken, and takes the verb mended" do
      case exercise table deviations tengo Regularised Preterite of
        Nothing -> fail "no exercise"
        Just e -> do
          e.slug `shouldEqual` Slug "error.regularised"
          e.label `shouldEqual` "an irregular made regular"
          e.prompt `shouldEqual` "yo tení mucho trabajo"
          e.hint `shouldEqual` "fix it · preterite"
          case e.answer of
            Checked c -> do
              c.expected `shouldEqual` "tuve"
              c.frame `shouldEqual` { before: "yo ", after: " mucho trabajo" }
              c.note `shouldEqual` "an irregular verb, conjugated as though it were regular"
            SelfGraded _ -> fail "self-graded"
            Choice _ -> fail "choice"

    it "keys by the kind, not the verb" do
      (exercise table deviations dicen StrongImperfect Imperfect <#> _.slug)
        `shouldEqual` Just (Slug "error.strong-imperfect")

    it "frames a verb in the middle" do
      (exercise table deviations dicen StrongWeak Preterite <#> _.prompt)
        `shouldEqual` Just "mi hermano dijió que no"

    -- The ending is the broken thing, so it cannot be what says who.
    -- `tengo` is not marked for a person shift, which is the point: whether
    -- a subject is missing is read off the words, not that flag.
    it "names the person of a sentence that has no subject" do
      (exercise table deviations tengo Regularised Preterite <#> frameOf)
        `shouldEqual` Just (Just { before: "yo ", after: " mucho trabajo" })

    it "and of one that has only a negation before the verb" do
      (exercise table deviations puedo Regularised Present <#> _.prompt)
        `shouldEqual` Just "yo no podo dormir"

    it "but gives one that has a subject no second" do
      (exercise table deviations pueden Regularised Present <#> _.prompt)
        `shouldEqual` Just "ellos no poden entrar"

    -- The pronoun is outside the box, so typing it too is not the fix.
    it "takes the verb alone" do
      (exercise table deviations tengo Regularised Preterite <#> \e -> matches (expectedOf e) "yo tuve")
        `shouldEqual` Just Wrong

  describe "the error-correction bank" do
    let yielded = exercises table deviations sentences

    it "has an item for every kind" do
      Array.nub (map _.slug yielded) `shouldEqual` map (\k -> Slug $ "error." <> slugPart k) kinds

    -- Which is what makes the kind the item: the verb is the example, and
    -- the pool is how you meet a different one each time.
    it "has at least three exercises for every item" do
      pools yielded
        # Array.filter (\p -> NonEmpty.length p.exercises < 3)
        # map _.slug
        # shouldEqual []

    it "never asks one sentence twice in a row" do
      let
        pairs = pools yielded >>= \p ->
          let es = NonEmpty.toArray p.exercises
          in Array.zip es (Array.drop 1 es)
      Array.filter (\(Tuple a b) -> frameOf a == frameOf b) pairs
        # map (\(Tuple a _) -> a.prompt)
        # shouldEqual []

    -- Every error, typed back unchanged, is wrong.
    it "asks nothing that is already right" do
      yielded
        # Array.filter (\e -> matches (expectedOf e) (brokenOf e) /= Wrong)
        # map _.prompt
        # shouldEqual []

    -- Two cells broken into the same string would make the fix a guess if
    -- the ending were all that said who. A subject says it now (#52), so
    -- this is no longer what keeps the fix determined; kept because it
    -- still holds, and a learner reading the ending should not be misled by
    -- it either. The imperfect's first and third persons share a form, and
    -- so share a fix, which is fine.
    it "never breaks two cells into one string with different fixes" do
      let
        verbs = Array.nub (map _.infinitive sentences)
        persons = [ Sg1, Sg2, Sg3, Pl1, Pl3 ]
        broken = do
          verb <- verbs
          tense <- Shift.tenses
          kind <- kinds
          person <- persons
          case mistake table deviations kind verb tense person, fixOf verb tense person of
            Just w, Just f -> [ { key: verb <> " " <> Shift.name tense <> " " <> w, fix: f } ]
            _, _ -> []
        ambiguous = Array.nub (map _.key broken) # Array.filter \k ->
          Array.length (Array.nub (map _.fix (Array.filter (\b -> b.key == k) broken))) > 1
      ambiguous `shouldEqual` []

    -- Before the verb, something that says who: the bank's own subject, or
    -- the pronoun put in front. Never nothing, and never just a negation.
    it "leaves no sentence without a subject" do
      let
        bare = do
          s <- sentences
          kind <- kinds
          tense <- Shift.tenses
          e <- Array.fromFoldable (exercise table deviations s kind tense)
          f <- Array.fromFoldable (frameOf e)
          if Array.elem (String.trim f.before) [ "", "no" ] then [ e.prompt ] else []
      bare `shouldEqual` []

    it "shares no item with the shifts or the paraphrase" do
      let
        others = Set.fromFoldable $ map _.slug $
          Shift.exercises table sentences
            <> PersonShift.exercises table sentences
            <> Paraphrase.exercises prompts
      Array.filter (\e -> Set.member e.slug others) yielded # map (slugToString <<< _.slug)
        # shouldEqual []
  where
    tengo = sentence "" "tengo" " mucho trabajo" "tener" Sg1
    dicen = sentence "mi hermano " "dice" " que no" "decir" Sg3
    puedo = sentence "no " "puedo" " dormir" "poder" Sg1
    pueden = sentence "ellos no " "pueden" " entrar" "poder" Pl3
    empiezo = sentence "" "empiezo" " a trabajar" "empezar" Sg1
    duerme = sentence "el niño " "duerme" " en su cama" "dormir" Sg3
    hace = sentence "ella " "hace" " la cena" "hacer" Sg3
    dicen3 = sentence "ellos " "dicen" " la verdad" "decir" Pl3
    llego = sentence "" "llego" " tarde" "llegar" Sg1
    busco = sentence "" "busco" " las llaves" "buscar" Sg1
    pide = sentence "ella " "pide" " la cuenta" "pedir" Sg3

    fixOf verb tense person = Array.find (\c -> c.infinitive == verb && c.tense == tense && c.person == person) table <#> _.form

    slugPart = case _ of
      Regularised -> "regularised"
      StrongImperfect -> "strong-imperfect"
      StrongWeak -> "strong-weak"
      Boot -> "boot"
      Orthographic -> "orthographic"
      StemIr -> "stem-ir"

expectedOf :: forall r. { answer :: Answer | r } -> String
expectedOf e = case e.answer of
  Checked c -> c.expected
  SelfGraded _ -> ""
  Choice _ -> ""

noteOf :: forall r. { answer :: Answer | r } -> String
noteOf e = case e.answer of
  Checked c -> c.note
  SelfGraded _ -> ""
  Choice _ -> ""

frameOf :: forall r. { answer :: Answer | r } -> Maybe { before :: String, after :: String }
frameOf e = case e.answer of
  Checked c -> Just c.frame
  SelfGraded _ -> Nothing
  Choice _ -> Nothing

-- | The prompt with its frame taken off: the error as it was typed into the
-- | sentence.
brokenOf :: forall r. { prompt :: String, answer :: Answer | r } -> String
brokenOf e = fromMaybe e.prompt do
  f <- frameOf e
  rest <- String.stripPrefix (String.Pattern f.before) e.prompt
  String.stripSuffix (String.Pattern f.after) rest

sentence :: String -> String -> String -> String -> Person -> Sentence
sentence before form after infinitive person =
  { before, form, after, infinitive, tense: Present, person, personShift: false }
