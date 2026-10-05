-- | The person shift: the tense shift turned the other way. A sentence, a
-- | person to move it to, and the verb typed in its new form, the tense held
-- | still. See #25.
-- |
-- | A sibling of `Flashcards.Verbs.Shift` rather than a second mode of it.
-- | Both make `Checked` exercises from a sentence and the table, but which
-- | coordinate moves decides the hint, the slug and which sentences qualify,
-- | and one function doing both would need a type only to say which.
-- |
-- | Pure, and given the table rather than importing it, so the spec can ask
-- | about a sentence the bank does not have.
module Flashcards.Verbs.PersonShift
  ( exercise
  , exercises
  , persons
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Flashcards.Exercise (Answer(..), Exercise)
import Flashcards.Types.Card (Slug(..))
import Flashcards.Verbs.Shift (Sentence)
import Flashcards.Verbs.Shift as Shift
import Flashcards.Verbs.Table (Cell, Person(..), formOf, pronoun)

-- | Every person there is, in the table's order.
persons :: Array Person
persons = [ Sg1, Sg2, Sg3, Pl1, Pl3 ]

-- | The sentence with its verb moved to `target`, asked of the item
-- | `person.infinitive.tense.target`.
-- |
-- | Namespaced, as the paraphrase's items are: the tense shift has
-- | `tener.preterite`, and over the same verbs and tenses this is a different
-- | question, so it keeps a different box.
-- |
-- | `Nothing` when there is nothing to ask: the sentence is not marked as
-- | taking a person shift, it is already in that person, or the table does not
-- | have the verb.
exercise :: Array Cell -> Sentence -> Person -> Maybe Exercise
exercise table sentence target
  | not sentence.personShift = Nothing
  | target == sentence.person = Nothing
  | otherwise =
      formOf sentence.infinitive sentence.tense target table <#> \expected ->
        { slug: Slug $ "person." <> sentence.infinitive <> "." <> Shift.name sentence.tense <> "." <> code target
        , label: sentence.infinitive <> " · " <> Shift.name sentence.tense <> " · " <> pronoun target
        , family: sentence.infinitive
        , cell: Just { infinitive: sentence.infinitive, tense: sentence.tense, person: target }
        , prompt: sentence.before <> sentence.form <> sentence.after
        , hint: pronoun target
        , answer: Checked
            { expected
            , frame: { before: sentence.before, after: sentence.after }
            , note: ""
            }
        }

-- | Every exercise the bank yields: each sentence marked for it into every
-- | person it is not already in, in the bank's order and then the order of
-- | `persons`.
exercises :: Array Cell -> Array Sentence -> Array Exercise
exercises table sentences =
  sentences >>= \s -> Array.mapMaybe (exercise table s) persons

-- | As the bank and the table spell it, `1p`.
code :: Person -> String
code = case _ of
  Sg1 -> "1s"
  Sg2 -> "2s"
  Sg3 -> "3s"
  Pl1 -> "1p"
  Pl3 -> "3p"
