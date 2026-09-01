-- | Lookups over a deck, built once. The deck is static, so these are computed
-- | at first use and reused for the life of the page.
module Flashcards.Deck
  ( Index
  , Repair
  , answersFor
  , card
  , demoteIneligible
  , index
  , isCanonical
  )
  where

import Prelude

import Data.Array as Array
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe, maybe)
import Data.Tuple (fst, snd)
import Data.Tuple.Nested ((/\))
import Data.Tuple.Nested (type (/\))
import Flashcards.Scheduler (graduationBox)
import Flashcards.Types.Card (Card, Rank)
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Progress (CardProgress, Progress)
import Flashcards.Types.Progress as Progress

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

type Repair =
  { progress :: Progress
  , demoted :: Int
  }

-- | Send back to recognition any card sitting in production that does not
-- | carry its English side.
-- |
-- | Progress saved before that rule existed contains them, and so can a backup
-- | from a device that predates it. Left alone they keep asking a prompt that
-- | cannot identify them.
-- |
-- | A demoted card returns to the box it occupied when it graduated, rather
-- | than keeping its production box: those answers were given against a prompt
-- | that could not distinguish the card from its siblings, so they are not
-- | evidence of anything. `seen`, `missed` and `lapses` are left as they are —
-- | those answers did happen, and the recognition and production parts of that
-- | history cannot be told apart after the fact.
demoteIneligible :: Index -> Progress -> Repair
demoteIneligible idx progress =
  { progress: Progress.mapWithRank fix progress
  , demoted: Array.length $ Array.filter stranded $ Progress.entries progress
  }
  where
    ineligible :: Rank -> CardProgress -> Boolean
    ineligible rank cp = case card rank idx of
      Just c -> cp.direction == Production && not (isCanonical c idx)
      Nothing -> false

    stranded :: Rank /\ CardProgress -> Boolean
    stranded pair = ineligible (fst pair) (snd pair)

    fix rank cp =
      if ineligible rank cp then cp { direction = Recognition, box = graduationBox }
      else cp
