-- | The tense shift: a sentence, a tense to move it to, and the verb typed in
-- | its new form. See #16.
-- |
-- | Pure, and given the table rather than importing it, so the spec can ask
-- | about a sentence the bank does not have.
module Flashcards.Verbs.Shift
  ( Sentence
  , exercise
  , exercises
  , tenses
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Flashcards.Exercise (Answer(..), Exercise)
import Flashcards.Types.Card (Slug(..))
import Flashcards.Verbs.Table (Cell, Person, Tense(..), formOf)

-- | One sentence of the bank, split around its verb. Generated into
-- | `Flashcards.Data.Sentences.Spanish` from `data/es-sentences.csv`, where
-- | the verb is written in brackets: `no [puedo] dormir`.
-- |
-- | `before` and `after` carry their own spaces, so the sentence is the three
-- | of them concatenated and nothing here has to know where words end.
type Sentence =
  { before :: String
  , form :: String
  , after :: String
  , infinitive :: String
  , tense :: Tense
  , person :: Person
  }

-- | What a sentence can be moved between. Not the subjunctive: it is a mood,
-- | not a tense, and where `tenga mucho trabajo` is grammatical at all it is
-- | an order, not the same sentence at another time. See #16.
tenses :: Array Tense
tenses = [ Present, Preterite, Imperfect ]

-- | The sentence with its verb moved to `target`, asked of the item
-- | `infinitive.target`.
-- |
-- | `Nothing` when there is nothing to ask: the sentence is already in that
-- | tense, the tense is not one a shift can reach, or the table does not have
-- | the verb.
exercise :: Array Cell -> Sentence -> Tense -> Maybe Exercise
exercise table sentence target
  | target == sentence.tense = Nothing
  | not (Array.elem target tenses) = Nothing
  | otherwise =
      formOf sentence.infinitive target sentence.person table <#> \expected ->
        { slug: Slug $ sentence.infinitive <> "." <> name target
        , prompt: sentence.before <> sentence.form <> sentence.after
        , hint: name target
        , frame: { before: sentence.before, after: sentence.after }
        , answer: Checked expected
        }

-- | Every exercise the bank yields: each sentence into every tense it is not
-- | already in, in the bank's order and then the order of `tenses`. Which
-- | slugs come out of this is what decides which items exist, so the bank is
-- | the curriculum.
exercises :: Array Cell -> Array Sentence -> Array Exercise
exercises table sentences =
  sentences >>= \s -> Array.mapMaybe (exercise table s) tenses

-- | As the slug spells it, `tener.preterite`, and as the prompt names it.
name :: Tense -> String
name = case _ of
  Present -> "present"
  Preterite -> "preterite"
  Imperfect -> "imperfect"
  Subjunctive -> "subjunctive"
