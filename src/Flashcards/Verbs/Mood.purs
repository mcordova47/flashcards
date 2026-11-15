-- | The trigger frame: the words that decide a mood, a person, and the verb
-- | typed in the form they call for. See #230 and the research on #28.
-- |
-- |     mi madre quiere que tú ___
-- |     → tener
-- |
-- | The aim is that a learner recognises the *kinds of meaning* that demand
-- | the subjunctive (a wish, a doubt, an emotion, a judgment, a purpose or a
-- | time still to come) and not particular phrases, so the bank is wide, in
-- | groups, with indicative triggers among them and minimal pairs where only
-- | the doubt differs. What a learner is asked is *whether* and then *how*:
-- | the hint is the infinitive alone, since naming the mood would make the
-- | decision for them.
-- |
-- | The expected form is a cell of the table, read with `formOf`, and never
-- | built here: the subjunctive cell after a subjunctive trigger, the present
-- | cell after an indicative one. The two never coincide in the table (the
-- | spec and `check-triggers` say so for every cell this module wires), so the
-- | form typed always says which mood was chosen.
-- |
-- | Pure, and given the table and the triggers rather than importing them, so
-- | the spec can ask about a trigger the bank does not have.
module Flashcards.Verbs.Mood
  ( Group(..)
  , Mood(..)
  , Trigger
  , exercise
  , exercises
  , groupLabel
  , interleave
  , prefix
  , slug
  , tense
  , verbs
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..), fromMaybe)
import Data.String as String
import Flashcards.Exercise (Answer(..), Exercise)
import Flashcards.Types.Card (Slug(..))
import Flashcards.Verbs.Coverage (Recommend(..), Verdict)
import Flashcards.Verbs.Table (Cell, Person(..), formOf, pronoun)
import Flashcards.Verbs.Table as Table

-- | The mood a trigger demands, which is the whole of the decision.
data Mood
  = Subjunctive
  | Indicative

derive instance Eq Mood

instance Show Mood where
  show Subjunctive = "Subjunctive"
  show Indicative = "Indicative"

-- | The kind of meaning that makes a trigger demand its mood. A group has one
-- | mood (`tools/trigger-source.mjs` holds the rows to that), and the reason
-- | shown after an answer names it, so the pattern is said and not left to be
-- | inferred.
data Group
  = Wish
  | Doubt
  | Emotion
  | Judgment
  | PurposeTime
  | Certainty
  | Fact

derive instance Eq Group
derive instance Ord Group

instance Show Group where
  show Wish = "Wish"
  show Doubt = "Doubt"
  show Emotion = "Emotion"
  show Judgment = "Judgment"
  show PurposeTime = "PurposeTime"
  show Certainty = "Certainty"
  show Fact = "Fact"

-- | One row of `data/es-triggers.csv`: the words before the gap, with a
-- | subject of their own (the same subject takes the infinitive, which would
-- | make the gap a trap), the mood they demand and why.
type Trigger =
  { trigger :: String
  , mood :: Mood
  , group :: Group
  , reason :: String
  }

-- | As the note names it. Must agree with `GROUPS` in
-- | `tools/trigger-source.mjs`, which the check prints.
groupLabel :: Group -> String
groupLabel = case _ of
  Wish -> "wish or request"
  Doubt -> "doubt or denial"
  Emotion -> "emotion"
  Judgment -> "impersonal judgment"
  PurposeTime -> "purpose, condition or future time"
  Certainty -> "belief or certainty"
  Fact -> "a fact or a reason"

-- | The tense of the table the form is read from.
tense :: Mood -> Table.Tense
tense = case _ of
  Subjunctive -> Table.Subjunctive
  Indicative -> Table.Present

-- | `mood.tener.1s`. An item is a verb and a person: its pool is the whole
-- | bank, so each sighting is a different trigger over the same cell, and a
-- | person who keeps slipping comes back on their own. Namespaced, as the
-- | person shift's are, since it asks over the same verbs.
slug :: String -> Person -> Slug
slug infinitive person = Slug $ prefix <> infinitive <> "." <> code person

prefix :: String
prefix = "mood."

-- | The trigger, the person and the verb, asked of the item `slug`.
-- |
-- | `Nothing` when the table does not have the cell the mood calls for, and
-- | when the trigger has no reason: the reason is what is said after the
-- | answer, and a frame that cannot say why teaches nothing about the kind of
-- | meaning. `tools/trigger-source.mjs` refuses such a row first.
exercise :: Array Cell -> String -> Person -> Trigger -> Maybe Exercise
exercise table infinitive person t
  | String.null (String.trim t.reason) = Nothing
  | otherwise =
  formOf infinitive (tense t.mood) person table <#> \expected ->
    { slug: slug infinitive person
    , label: infinitive <> " · mood · " <> pronoun person
    , family: infinitive
    , cell: Just { infinitive, tense: tense t.mood, person }
    -- Not the trigger, which is in the frame, and not anything that names
    -- the mood.
    , prompt: "Complete the sentence"
    , hint: infinitive
    , answer: Checked
        { expected
        , frame: { before: t.trigger <> " " <> pronoun person <> " ", after: "" }
        , note: groupLabel t.group <> " · " <> t.reason
        }
    }

-- | Every exercise for the verbs given, a pool for each verb and person, most
-- | common verb first as the caller ranks them.
-- |
-- | Each pool is the whole bank, in an order made to vary: the groups take
-- | turns (`interleave`), so that consecutive sightings are rarely the same
-- | kind of meaning and an indicative one comes round every few, and each pool
-- | starts somewhere else (`rotate`), so that the same verb and person are
-- | not met with the same trigger in every verb's first week. `Exercise.pick`
-- | turns a pool by how many times it has been graded.
exercises :: Array Cell -> Array Trigger -> Array String -> Array Exercise
exercises table triggers infinitives =
  Array.mapWithIndex (\v infinitive ->
    Array.mapWithIndex (\p person ->
      Array.mapMaybe (exercise table infinitive person)
        (rotate (v + 4 * p) (interleave triggers))) persons) infinitives
    # join # join
  where
    persons = [ Sg1, Sg2, Sg3, Pl1, Pl3 ]

-- | The same triggers with the groups taking turns, each keeping its own
-- | order: one of each group in the order the groups first appear, and again.
interleave :: Array Trigger -> Array Trigger
interleave triggers = go (Array.nub (map _.group triggers) <#> \g -> Array.filter (\t -> t.group == g) triggers)
  where
    go lists = case Array.filter (not <<< Array.null) lists of
      [] -> []
      live -> Array.mapMaybe Array.head live <> go (map (Array.drop 1) live)

-- | Moved round so that it starts `n` along.
rotate :: forall a. Int -> Array a -> Array a
rotate n xs = case Array.length xs of
  0 -> xs
  len -> let k = n `mod` len in Array.drop k xs <> Array.take k xs

-- | The verbs the bank asks: the `count` most common whose subjunctive the
-- | coverage recommends drilling in every person. Limited, so that the
-- | schedule gains verbs a few at a time (#28 puts the recommended cells at
-- | 140 over 29 verbs), and to verbs the whole row is worth drilling in, since
-- | a pool of five persons with `dar`'s three skipped cells would ask forms
-- | the ending rule already gives.
verbs :: Int -> (String -> Maybe Int) -> Array Verdict -> Array String
verbs count rank verdicts =
  Array.take count $ Array.sortWith (fromMaybe top <<< rank) $ Array.filter wholeRow candidates
  where
    candidates = Array.nub $ map _.infinitive $ Array.filter (\v -> v.tense == Table.Subjunctive) verdicts
    wholeRow infinitive =
      let row = Array.filter (\v -> v.infinitive == infinitive && v.tense == Table.Subjunctive) verdicts
      in Array.length row == 5 && Array.all (\v -> v.recommend == Drill) row

-- | As the table spells it.
code :: Person -> String
code = case _ of
  Sg1 -> "1s"
  Sg2 -> "2s"
  Sg3 -> "3s"
  Pl1 -> "1p"
  Pl3 -> "3p"
