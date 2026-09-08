module Flashcards.Types.Card
  ( Card
  , Rank(..)
  , Slug(..)
  , rankToInt
  , slugToString
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

-- | `word` is the foreign side, whichever language the deck is in. It is the
-- | recognition prompt, and every deck guarantees it unique.
-- | A card's identity, and what saved progress is keyed by.
-- |
-- | Derived from the foreign word's spelling when the card is first written
-- | down, then frozen: rank is a position and moves whenever the deck is
-- | edited, so it cannot serve. Once frozen a slug is an opaque id, and the
-- | derivation is only there so that a stale one is legible rather than
-- | inscrutable — `concrete` beside `concreto` says what happened.
newtype Slug = Slug String

derive newtype instance Eq Slug
derive newtype instance Ord Slug
derive newtype instance Show Slug

slugToString :: Slug -> String
slugToString (Slug s) = s

type Card =
  { rank :: Rank
  , slug :: Slug
  , english :: String
  , word :: String
  -- | A sentence using the word, or empty where the deck has none. Shown only
  -- | after the reveal: most examples contain the word, so before it they
  -- | would hand over the answer.
  , example :: String
  }

rankToInt :: Rank -> Int
rankToInt (Rank n) = n
