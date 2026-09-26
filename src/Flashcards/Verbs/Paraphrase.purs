-- | The paraphrase drill: an English prompt, a model answer, and a rubric
-- | saying why the answer is what it is. See #10; the corpus is #17.
-- |
-- | Many answers are valid, so there is nothing to compare against — which is
-- | why this looked like the exercise that needed a model in the loop. It does
-- | not. It needs a rubric instead of an answer: *did I use ser* is a question
-- | you can answer about your own sentence, where *was I right* is not.
-- |
-- | Pure, and given its prompts rather than importing them, so the spec can
-- | ask about a prompt the corpus does not have.
module Flashcards.Verbs.Paraphrase
  ( Prompt
  , Trap(..)
  , exercise
  , exercises
  , rubric
  )
  where

import Prelude

import Flashcards.Exercise (Answer(..), Exercise, Rubric)
import Flashcards.Types.Card (Slug(..))
import Flashcards.Verbs.Table (Person(..), Tense(..))

-- | Which of the three targets is the live decision, and so the only line of
-- | the rubric that is phrased as a choice. A prompt is written *for* one
-- | trap; the rest of the row is reported as fact. See #17.
data Trap
  = OnVerb
  | OnTense

derive instance Eq Trap

instance Show Trap where
  show OnVerb = "OnVerb"
  show OnTense = "OnTense"

-- | One row of `data/es-paraphrase.csv`.
-- |
-- | `id` is frozen when the row is written and is never derived from `asked`
-- | or `model`, because #22 expects those to be reworded in use and a
-- | reworded row is the same item. The same reason a card is keyed by slug
-- | and not by rank.
-- |
-- | `against` is the wrong choice a learner reaches for: a verb when the trap
-- | is `OnVerb`, a tense when it is `OnTense`.
type Prompt =
  { id :: String
  , asked :: String
  , model :: String
  , verb :: String
  , tense :: Tense
  , person :: Person
  , trap :: Trap
  , against :: String
  }

-- | Why the model answer is what it is, in three lines.
-- |
-- | Only the trap is phrased as a choice — *ser, not estar* — because only one
-- | of the three was in doubt. Saying "imperfect, not preterite" on a prompt
-- | whose tense was never in question teaches a confusion that was not there,
-- | and makes the line that matters harder to find.
rubric :: Prompt -> Rubric
rubric p =
  [ case p.trap of
      OnVerb -> p.verb <> ", not " <> p.against
      OnTense -> p.verb
  , case p.trap of
      OnTense -> tense p.tense <> ", not " <> p.against
      OnVerb -> tense p.tense
  , person p.person
  ]

-- | Asked of the item `paraphrase.<id>`.
-- |
-- | Namespaced, and deliberately not `verb.tense`: the tense shift already
-- | uses that, over verbs and tenses these prompts share, so one slug space
-- | would have a paraphrase credit a shift and the other way about. They are
-- | different skills and keep different boxes.
exercise :: Prompt -> Exercise
exercise p =
  { slug: Slug $ "paraphrase." <> p.id
  , prompt: p.asked
  -- Nothing to say before the reveal. The prompt is the whole question, and a
  -- hint here would name the trap, which is the answer.
  , hint: ""
  , answer: SelfGraded { model: p.model, rubric: rubric p }
  }

-- | Every exercise the corpus yields, in its order — one prompt, one item, so
-- | each is scheduled on how hard it turns out to be rather than sharing a box
-- | with the others that spring the same trap.
exercises :: Array Prompt -> Array Exercise
exercises = map exercise

tense :: Tense -> String
tense = case _ of
  Present -> "present"
  Preterite -> "preterite"
  Imperfect -> "imperfect"
  Subjunctive -> "subjunctive"

person :: Person -> String
person = case _ of
  Sg1 -> "first person singular"
  Sg2 -> "second person singular"
  Sg3 -> "third person singular"
  Pl1 -> "first person plural"
  Pl3 -> "third person plural"
