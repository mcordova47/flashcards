-- | Error correction: a sentence with its verb broken on purpose, and the
-- | verb typed back mended. See #26.
-- |
-- | Generated backwards. The answer is a cell of the table and the mistake
-- | is made from it, so nothing is authored and the fix is known because the
-- | error was deliberate. What *is* authored is the list of kinds below,
-- | which is the teaching: each is a mistake learners make, and the drill is
-- | learning to see it.
-- |
-- | The prompt names the tense. Without it the fix is not determined:
-- | `tení mucho trabajo` is a regularised `tuve` or a clipped `tenía`, and
-- | both mended sentences are good Spanish.
-- |
-- | Pure, and given the table and its deviations rather than importing them,
-- | so the spec can ask about a verb the table does not have.
module Flashcards.Verbs.Correction
  ( Kind(..)
  , exercise
  , exercises
  , kinds
  , mistake
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.String as String
import Flashcards.Exercise (Answer(..), Exercise, Verdict(..), matches)
import Flashcards.Types.Card (Slug(..))
import Flashcards.Verbs.Shift (Sentence)
import Flashcards.Verbs.Shift as Shift
import Flashcards.Verbs.Table (Cell, Deviation, Person(..), Tense(..), formOf)

-- | The mistakes, each one a thing learners do. Every error is made from a
-- | cell `check-verbs` reports as deviating — the regularised irregular *is*
-- | its "(not X)", and the others are built from the stems it flags — so a
-- | verb the review calls regular can yield none of them.
-- |
-- | Not here, and why:
-- |
-- | - **Accents.** `matches` forgives a missing accent, on purpose, so an
-- |   accent could not be the thing to fix: `tenia` would be accepted as the
-- |   fix for `tenia`. Grading strictly here instead would fail a missing
-- |   accent on every kind, which is what #16 decided against.
-- | - **Orthographic** (`llegé`, `buscé`) and the **-ir preterite stem
-- |   change** (`dormió`). Real, and in the table, but no sentence in the
-- |   bank has a verb that makes them.
data Kind
  -- | `teno` for `tengo`, `tení` for `tuve`: the regular pattern applied to
  -- | a verb that has its own form. The commonest of all, and the one a
  -- | learner is likeliest to have been taught out of and to slip back into.
  = Regularised
  -- | `tuvía` for `tenía`: the preterite's irregular stem carried into the
  -- | imperfect, which for all of these verbs is regular. Learners who know
  -- | a verb is irregular over-apply it, which is why #12 warned against
  -- | dropping the regular imperfects.
  | StrongImperfect
  -- | `tuví` for `tuve`, `dijieron` for `dijeron`: the irregular stem, right,
  -- | with the regular endings. These stems take unstressed `-e` and `-o`,
  -- | and `-eron` after `j`, and the stressed regular endings are what the
  -- | ear expects.
  | StrongWeak
  -- | `tienemos` for `tenemos`: the stem change carried into *nosotros*,
  -- | which keeps the infinitive's stem. The change is learned from the
  -- | forms heard most, and those are exactly the ones that have it.
  | Boot

derive instance Eq Kind

instance Show Kind where
  show Regularised = "Regularised"
  show StrongImperfect = "StrongImperfect"
  show StrongWeak = "StrongWeak"
  show Boot = "Boot"

-- | In the order they are introduced: the commonest first.
kinds :: Array Kind
kinds = [ Regularised, StrongWeak, StrongImperfect, Boot ]

-- | The wrong form a kind makes of one cell, if it makes one.
-- |
-- | `Nothing` when the kind does not apply to the cell, and also when what it
-- | makes is a form the verb really has, in any tense a sentence can be in:
-- |
-- | - **the fix itself**, as `tuviste` is for a strong stem with regular
-- |   endings — there is nothing wrong to see;
-- | - **the fix but for an accent**, as `estas` is for `estás` — `matches`
-- |   forgives it, so typing the error back unchanged would pass;
-- | - **another tense's form**, as `estamos` is for `estuvimos` — the
-- |   sentence on screen is then good Spanish, and mending it is a tense
-- |   shift, which is a different drill.
-- |
-- | And never of `ser` or `ir`, which share no stem with their infinitive:
-- | regularised, `ir` gives `o a la ciudad`, and nobody says that.
mistake :: Array Cell -> Array Deviation -> Kind -> String -> Tense -> Person -> Maybe String
mistake table deviations kind infinitive tense person
  | Array.elem infinitive suppletive = Nothing
  | not (Array.elem tense Shift.tenses) = Nothing
  | otherwise = do
      _ <- formOf infinitive tense person table
      wrong <- case kind of
        Regularised ->
          _.regular <$> deviation tense person
        StrongImperfect | tense == Imperfect ->
          strongStem <#> (_ <> imperfect person)
        StrongWeak | tense == Preterite ->
          strongStem <#> (_ <> weak person)
        Boot | tense == Present && person == Pl1 ->
          bootStem <#> (_ <> nosotros)
        _ ->
          Nothing
      if Array.any (\c -> matches c.form wrong /= Wrong) real then Nothing else Just wrong
  where
    real = Array.filter (\c -> c.infinitive == infinitive && Array.elem c.tense Shift.tenses) table

    deviation t p = Array.find (\d -> d.infinitive == infinitive && d.tense == t && d.person == p) deviations

    cell t p = do
      _ <- deviation t p
      formOf infinitive t p table

    -- `tuv` from `tuve` and `tuvo`: a preterite whose first and third
    -- persons end unstressed is a strong one, and what precedes the `-e` is
    -- its stem. A regular preterite stresses both, `-é`/`-í` and `-ó`/`-ió`.
    strongStem = do
      first <- cell Preterite Sg1
      third <- cell Preterite Sg3
      _ <- String.stripSuffix (String.Pattern "o") third
      String.stripSuffix (String.Pattern "e") first

    -- `tien` from `tiene`: the stem the singular carries, where it changed.
    -- A third person that does not deviate has no change to carry.
    bootStem = do
      third <- cell Present Sg3
      String.stripSuffix (String.Pattern (if group == "ar" then "a" else "e")) third

    group = String.drop (String.length infinitive - 2) infinitive

    nosotros = case group of
      "ar" -> "amos"
      "er" -> "emos"
      _ -> "imos"

-- | Asked of the item `error.<kind>`, with the sentence's verb put into
-- | `tense` and broken.
-- |
-- | The item is the kind, not the verb: what is being learned is to see a
-- | regularised irregular, and `tener` is the example. So a handful of items
-- | with large pools, and the tense shift's `tener.preterite` is a different
-- | question over the same cell.
-- |
-- | The sentence's own tense does not matter. A bank sentence can carry
-- | another tense's form, which is what the tense shift already depends on.
exercise :: Array Cell -> Array Deviation -> Sentence -> Kind -> Tense -> Maybe Exercise
exercise table deviations sentence kind tense = do
  wrong <- mistake table deviations kind sentence.infinitive tense sentence.person
  fix <- formOf sentence.infinitive tense sentence.person table
  pure
    { slug: Slug $ "error." <> code kind
    , label: label kind
    , prompt: sentence.before <> wrong <> sentence.after
    , hint: "fix it · " <> Shift.name tense
    , answer: Checked
        { expected: fix
        , frame: { before: sentence.before, after: sentence.after }
        , note: note kind
        }
    }

-- | Every exercise the bank yields, by kind, then tense, then the bank's
-- | order. Tense before sentence so that `pick`, turning through a pool,
-- | moves to another sentence each time rather than asking one sentence in
-- | two tenses back to back.
exercises :: Array Cell -> Array Deviation -> Array Sentence -> Array Exercise
exercises table deviations sentences = do
  kind <- kinds
  tense <- Shift.tenses
  Array.mapMaybe (\s -> exercise table deviations s kind tense) sentences

suppletive :: Array String
suppletive = [ "ser", "ir" ]

-- | Unstressed where a strong preterite's are, stressed where the regular
-- | ones are: the difference is the mistake.
weak :: Person -> String
weak = case _ of
  Sg1 -> "í"
  Sg2 -> "iste"
  Sg3 -> "ió"
  Pl1 -> "imos"
  Pl3 -> "ieron"

-- | The `-er`/`-ir` imperfect, which is what a strong stem sounds like it
-- | wants — every one of them but `estar`'s belongs to an `-er` or `-ir` verb.
imperfect :: Person -> String
imperfect = case _ of
  Sg1 -> "ía"
  Sg2 -> "ías"
  Sg3 -> "ía"
  Pl1 -> "íamos"
  Pl3 -> "ían"

code :: Kind -> String
code = case _ of
  Regularised -> "regularised"
  StrongImperfect -> "strong-imperfect"
  StrongWeak -> "strong-weak"
  Boot -> "boot"

-- | As the progress sheet lists what keeps slipping.
label :: Kind -> String
label = case _ of
  Regularised -> "an irregular made regular"
  StrongImperfect -> "a preterite stem in the imperfect"
  StrongWeak -> "a preterite stem with regular endings"
  Boot -> "a stem change in nosotros"

-- | Said once the answer is in, and not before: naming the mistake would
-- | give the fix away.
note :: Kind -> String
note = case _ of
  Regularised -> "an irregular verb, conjugated as though it were regular"
  StrongImperfect -> "the irregular stem belongs to the preterite; the imperfect is regular"
  StrongWeak -> "an irregular preterite stem takes -e and -o, and -eron after j"
  Boot -> "nosotros keeps the infinitive's stem"
