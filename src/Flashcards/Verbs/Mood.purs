-- | The trigger sentence: a whole hand-written sentence with the verb as the
-- | blank, the infinitive as the hint, and the verb typed in the form its
-- | trigger calls for. See #230 and #241.
-- |
-- |     mi madre quiere que tú ___ temprano
-- |     → venir
-- |
-- | The first version joined a trigger, a person and a verb mechanically, and
-- | many of the joins meant nothing (`mi madre quiere que yo quiera`). A
-- | sentence is written by a person, so it says something.
-- |
-- | The aim is still that a learner recognises the *kinds of meaning* that
-- | demand the subjunctive (a wish, a doubt, an emotion, a judgment, a purpose
-- | or a time still to come) and not particular phrases, so the sentences are
-- | in groups, with indicative ones among them and minimal pairs where only the
-- | doubt differs. What a learner is asked is *whether* and then *how*: the
-- | hint is the infinitive alone, since naming the mood would make the decision
-- | for them.
-- |
-- | The expected form is a cell of the table, read with `formOf`, and never
-- | typed in the data: the subjunctive cell after a subjunctive trigger, the
-- | present cell after an indicative one. The two never coincide in the table
-- | (the spec and `check-triggers` say so for every cell this module wires), so
-- | the form typed always says which mood was chosen.
-- |
-- | Pure, and given the table and the sentences rather than importing them, so
-- | the spec can ask about a sentence the bank does not have.
module Flashcards.Verbs.Mood
  ( Group(..)
  , Mood(..)
  , Sentence
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

-- | One row of `data/es-trigger-sentences.csv`, with what its trigger says
-- | (`data/es-triggers.csv`): the mood it demands and why, and the sentence
-- | split at its blank. The blank's form is not here, and the sentence has a
-- | subject of its own for the main clause (the same subject takes the
-- | infinitive, which would make the blank a trap).
type Sentence =
  { trigger :: String
  , mood :: Mood
  , group :: Group
  , reason :: String
  , verb :: String
  , person :: Person
  , before :: String
  , after :: String
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

-- | `mood.tener.1s`. An item is a verb and a person: its pool is the sentences
-- | written for it, so each sighting is a different sentence over the same
-- | cell, and a person who keeps slipping comes back on their own. The items
-- | are the ones #230 made and keep their ids, so a learner's progress
-- | stays (#241). Namespaced, as the
-- | person shift's are, since it asks over the same verbs.
slug :: String -> Person -> Slug
slug infinitive person = Slug $ prefix <> infinitive <> "." <> code person

prefix :: String
prefix = "mood."

-- | The sentence, asked of the item `slug`: its blank, and the form the table
-- | has for it.
-- |
-- | `Nothing` when the table does not have the cell the mood calls for, and
-- | when the sentence has no reason: the reason is what is said after the
-- | answer, and a sentence that cannot say why teaches nothing about the kind
-- | of meaning. `tools/trigger-source.mjs` refuses such a row first.
exercise :: Array Cell -> Sentence -> Maybe Exercise
exercise table s
  | String.null (String.trim s.reason) = Nothing
  | otherwise =
  formOf s.verb (tense s.mood) s.person table <#> \expected ->
    { slug: slug s.verb s.person
    , label: s.verb <> " · mood · " <> pronoun s.person
    , family: s.verb
    , cell: Just { infinitive: s.verb, tense: tense s.mood, person: s.person }
    -- Not the trigger, which is in the sentence, and not anything that names
    -- the mood.
    , prompt: "Complete the sentence"
    , hint: s.verb
    , answer: Checked
        { expected
        , frame: { before: s.before, after: s.after }
        , note: groupLabel s.group <> " · " <> s.reason
        }
    }

-- | Every exercise for the verbs given, a pool for each verb and person, most
-- | common verb first as the caller ranks them.
-- |
-- | A pool is the sentences written for that verb and person, in an order made
-- | to vary: the groups take turns (`interleave`), so that consecutive
-- | sightings are rarely the same kind of meaning, and each pool starts
-- | somewhere else (`rotate`), so that the pools of the nine verbs do not all
-- | open on the same kind. `Exercise.pick` turns a pool by how many times it
-- | has been graded, so the same verb and person are met with a different
-- | sentence on every sighting until the pool has been through.
exercises :: Array Cell -> Array Sentence -> Array String -> Array Exercise
exercises table sentences infinitives =
  Array.mapWithIndex (\v infinitive ->
    Array.mapWithIndex (\p person ->
      Array.mapMaybe (exercise table)
        (rotate (v + p) (interleave (Array.filter (\s -> s.verb == infinitive && s.person == person) sentences)))) persons) infinitives
    # join # join
  where
    persons = [ Sg1, Sg2, Sg3, Pl1, Pl3 ]

-- | The same sentences with the groups taking turns, each keeping its own
-- | order: one of each group in the order the groups first appear, and again.
interleave :: forall r. Array { group :: Group | r } -> Array { group :: Group | r }
interleave sentences = go (Array.nub (map _.group sentences) <#> \g -> Array.filter (\t -> t.group == g) sentences)
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
