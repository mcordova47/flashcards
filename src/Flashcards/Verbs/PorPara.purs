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
  , takes
  , word
  )
  where

import Prelude

import Data.Maybe (Maybe(..))
import Flashcards.Exercise (Answer(..), Exercise)
import Flashcards.Types.Card (Slug(..))

-- | What gets scheduled. Mostly a contrast: one of the pairs of senses that
-- | English says with one word and Spanish splits. Not a sentence, or the
-- | learner passes by remembering that *this* one takes `por`; and not one
-- | side of a pair, because the mistake worth spacing is taking one side for
-- | the other.
-- |
-- | And a few senses with no opposite, which are a difficulty without being a
-- | contrast (#43). *Twice a week* has no `para` reading to be mistaken for,
-- | but nothing in the English says `por` either. What these teach is which
-- | preposition the sense takes, and once that is learned they climb the
-- | boxes and get out of the way.
-- |
-- | Each has a pool of sentences and `Exercise.pick` turns it.
data Item
  = CausePurpose
  | DurationDeadline
  | ThroughTowards
  | ExchangeRecipient
  | Per
  | Means

derive instance Eq Item

instance Show Item where
  show CausePurpose = "CausePurpose"
  show DurationDeadline = "DurationDeadline"
  show ThroughTowards = "ThroughTowards"
  show ExchangeRecipient = "ExchangeRecipient"
  show Per = "Per"
  show Means = "Means"

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

-- | The one preposition a sense takes, or `Nothing` for a contrast, which
-- | takes both. `tools/por-para-source.mjs` says the same, and
-- | `check-por-para` holds the bank to it.
-- |
-- | Not shown: the hint is `por / para` either way, because it is the answer
-- | space, and a hint that told a sense from a contrast would be the answer.
takes :: Item -> Maybe Preposition
takes = case _ of
  CausePurpose -> Nothing
  DurationDeadline -> Nothing
  ThroughTowards -> Nothing
  ExchangeRecipient -> Nothing
  Per -> Just Por
  Means -> Just Por

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
  Per -> "per"
  Means -> "means"

-- | As the progress sheet names it, `por / para · cause vs purpose`.
label :: Item -> String
label c = "por / para · " <> case c of
  CausePurpose -> "cause vs purpose"
  DurationDeadline -> "duration vs deadline"
  ThroughTowards -> "through vs towards"
  ExchangeRecipient -> "exchange vs recipient"
  Per -> "per"
  Means -> "by means of"

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
  -- One decision, whichever sense asks it: two in a row is the same choice
  -- made twice.
  , family: "por / para"
  , cell: Nothing
  , prompt: s.english
  , hint: "por / para"
  , answer: Checked
      { expected: word s.answer
      , frame: { before: s.before, after: s.after }
      , note: ""
      }
  }

-- | Every exercise the bank yields, in its order: one per sentence, several
-- | per item.
exercises :: Array Sentence -> Array Exercise
exercises = map exercise
