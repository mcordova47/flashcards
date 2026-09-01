-- | Lookups over a deck, built once. The deck is static, so these are computed
-- | at first use and reused for the life of the page.
module Flashcards.Deck
  ( Index
  , answersFor
  , card
  , index
  , isCanonical
  )
  where

import Prelude

import Data.Array as Array
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Tuple.Nested ((/\))
import Flashcards.Types.Card (Card, Rank)

type Index =
  { byRank :: Map Rank Card
  , answers :: Map String (Array String)
  }

index :: Array Card -> Index
index deck =
  { byRank: Map.fromFoldable $ deck <#> \c -> c.rank /\ c
  , answers: Array.foldl collect Map.empty deck
  }
  where
    -- Appended rather than prepended, so the answers stay in frequency order:
    -- the most common reading of an English word comes first.
    collect acc c =
      Map.alter (Just <<< maybe [ c.spanish ] (_ <> [ c.spanish ])) c.english acc

card :: Rank -> Index -> Maybe Card
card rank = Map.lookup rank <<< _.byRank

-- | Every Spanish word that legitimately answers this English prompt.
-- |
-- | 61 English sides in the deck map to more than one — `that` covers six —
-- | so a production prompt cannot expect a single answer, and the reveal has
-- | to show the whole set to grade yourself against.
answersFor :: String -> Index -> Array String
answersFor english = fromMaybe [] <<< Map.lookup english <<< _.answers

-- | Whether this is the card asked in production for its English side.
-- |
-- | Several cards can share one gloss — six share `that` — and in production
-- | the gloss is the whole prompt, so the siblings are indistinguishable from
-- | each other. Asking all of them would credit you six times over for
-- | producing one word. The most frequent member carries the question; see
-- | `Flashcards.Scheduler.Graduation`.
isCanonical :: Card -> Index -> Boolean
isCanonical c = (_ == Just c.spanish) <<< Array.head <<< answersFor c.english
