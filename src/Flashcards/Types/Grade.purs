module Flashcards.Types.Grade
  ( Grade(..)
  )
  where

import Prelude

-- | Two grades, not three. A third option is a decision tax paid on every
-- | single card, and Leitner does not need the extra resolution.
data Grade
  = Again
  | GotIt

derive instance Eq Grade
derive instance Ord Grade

instance Show Grade where
  show Again = "Again"
  show GotIt = "GotIt"
