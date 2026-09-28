-- | por or para: a sentence with a gap, the English that says which sense it
-- | is, and the preposition typed into the gap. See #18.
-- |
-- | Not a verb drill, but it lives with them: it is checked rather than
-- | self-graded, it is scheduled by the same machinery, and it has nowhere
-- | else to go.
-- |
-- | Pure, and given its sentences rather than importing them, so the spec can
-- | ask about a sentence the bank does not have.
module Flashcards.Verbs.PorPara
  ( Item(..)
  , Preposition(..)
  , Sentence
  , exercise
  , exercises
  , label
  , slug
  , word
  )
  where

import Prelude

import Flashcards.Exercise (Answer(..), Exercise)
import Flashcards.Types.Card (Slug(..))

-- | What gets scheduled: one of the pairs of senses that English says with
-- | one word and Spanish splits. Not a sentence, or the learner passes by
-- | remembering that *this* one takes `por`; and not one side of a pair,
-- | because the mistake worth spacing is taking one side for the other.
-- |
-- | Each has a pool of sentences, some answered by each side, and
-- | `Exercise.pick` turns it.
data Item
  = CausePurpose
  | DurationDeadline
  | ThroughTowards
  | ExchangeRecipient

derive instance Eq Item

instance Show Item where
  show CausePurpose = "CausePurpose"
  show DurationDeadline = "DurationDeadline"
  show ThroughTowards = "ThroughTowards"
  show ExchangeRecipient = "ExchangeRecipient"

data Preposition
  = Por
  | Para

derive instance Eq Preposition

instance Show Preposition where
  show Por = "Por"
  show Para = "Para"

-- | One row of `data/es-por-para.csv`, split around its gap.
-- |
-- | `english` is the prompt, and what makes the answer the answer: `lo hice
-- | [ ] ti` takes either preposition, and only *because of you* or *for your
-- | benefit* says which.
type Sentence =
  { before :: String
  , answer :: Preposition
  , after :: String
  , english :: String
  , item :: Item
  }

-- | As it is typed.
word :: Preposition -> String
word = case _ of
  Por -> "por"
  Para -> "para"

-- | `porpara.cause-purpose`. Namespaced, as the person shift's and the
-- | paraphrase's are, though no other exercise could spell one of these.
slug :: Item -> Slug
slug c = Slug $ "porpara." <> case c of
  CausePurpose -> "cause-purpose"
  DurationDeadline -> "duration-deadline"
  ThroughTowards -> "through-towards"
  ExchangeRecipient -> "exchange-recipient"

-- | As the progress sheet names it, `por / para · cause vs purpose`.
label :: Item -> String
label c = "por / para · " <> case c of
  CausePurpose -> "cause vs purpose"
  DurationDeadline -> "duration vs deadline"
  ThroughTowards -> "through vs towards"
  ExchangeRecipient -> "exchange vs recipient"

-- | The English as the question, and the Spanish with a box where the
-- | preposition goes.
-- |
-- | The prompt is the English and not the Spanish: the typed view heads the
-- | page with the prompt, and the Spanish sentence would have the answer in
-- | it.
exercise :: Sentence -> Exercise
exercise s =
  { slug: slug s.item
  , label: label s.item
  , prompt: s.english
  , hint: "por / para"
  , answer: Checked
      { expected: word s.answer
      , frame: { before: s.before, after: s.after }
      }
  }

-- | Every exercise the bank yields, in its order: one per sentence, several
-- | per contrast.
exercises :: Array Sentence -> Array Exercise
exercises = map exercise
