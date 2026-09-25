-- | What a conjugation table is made of. The table itself is generated into
-- | `Flashcards.Data.Verbs.Spanish` from `data/es-verbs.csv`; this is where
-- | its types live, since a generated module cannot be where they are defined.
module Flashcards.Verbs.Table
  ( Cell
  , Person(..)
  , Tense(..)
  , formOf
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe)

-- | The four that carry the difficulty. Future and conditional are regular
-- | for almost every verb and are better added later than padded in now.
data Tense
  = Present
  | Preterite
  | Imperfect
  | Subjunctive

derive instance Eq Tense
derive instance Ord Tense

instance Show Tense where
  show Present = "Present"
  show Preterite = "Preterite"
  show Imperfect = "Imperfect"
  show Subjunctive = "Subjunctive"

-- | Five, not six: no *vosotros*, since the deck prefers es-MX. `Sg3` and
-- | `Pl3` carry *usted* and *ustedes*.
data Person
  = Sg1
  | Sg2
  | Sg3
  | Pl1
  | Pl3

derive instance Eq Person
derive instance Ord Person

instance Show Person where
  show Sg1 = "Sg1"
  show Sg2 = "Sg2"
  show Sg3 = "Sg3"
  show Pl1 = "Pl1"
  show Pl3 = "Pl3"

type Cell =
  { infinitive :: String
  , tense :: Tense
  , person :: Person
  -- | Accented exactly. Grading may forgive a missing accent; the table
  -- | does not have one to forgive.
  , form :: String
  }

-- | The form in one cell, if the table has that verb.
formOf :: String -> Tense -> Person -> Array Cell -> Maybe String
formOf infinitive tense person =
  map _.form <<< Array.find \c -> c.infinitive == infinitive && c.tense == tense && c.person == person
