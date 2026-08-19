module Flashcards.Types.Card
  ( Card
  , Rank(..)
  , rankToInt
  )
  where

import Prelude

-- | A card's position in the frequency list: 1 is the most common word. This
-- | doubles as the card's stable identity, so progress survives a deck resync
-- | as long as the ordering does.
newtype Rank = Rank Int

derive newtype instance Eq Rank
derive newtype instance Ord Rank
derive newtype instance Show Rank

type Card =
  { rank :: Rank
  , english :: String
  , spanish :: String
  }

rankToInt :: Rank -> Int
rankToInt (Rank n) = n
