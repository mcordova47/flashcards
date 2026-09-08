-- | Lookups over a deck, built once. The deck is static, so these are computed
-- | at first use and reused for the life of the page.
module Flashcards.Deck
  ( Adoption
  , Index
  , Repair
  , adopt
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
import Data.Tuple.Nested (type (/\), (/\))
import Flashcards.Scheduler (graduationBox)
import Flashcards.Types.Card (Card, Rank, Slug)
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Progress (CardProgress, Progress, Saved)
import Flashcards.Types.Progress as Progress

type Index =
  { bySlug :: Map Slug Card
  -- | Only used to place progress written before v5, which named its cards by
  -- | position. See `adopt`.
  , byRank :: Map Rank Card
  , answers :: Map String (Array String)
  }

index :: Array Card -> Index
index deck =
  { bySlug: Map.fromFoldable $ deck <#> \c -> c.slug /\ c
  , byRank: Map.fromFoldable $ deck <#> \c -> c.rank /\ c
  , answers: Array.foldl collect Map.empty deck
  }
  where
    -- Appended rather than prepended, so the answers stay in frequency order:
    -- the most common reading of an English word comes first.
    collect acc c =
      Map.alter (Just <<< maybe [ c.word ] (_ <> [ c.word ])) c.english acc

card :: Slug -> Index -> Maybe Card
card slug = Map.lookup slug <<< _.bySlug

-- | Every foreign word that legitimately answers this English prompt.
-- |
-- | Some English sides map to more than one, so a production prompt cannot
-- | expect a single answer and the reveal has to show the whole set to grade
-- | yourself against.
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
isCanonical c = (_ == Just c.word) <<< Array.head <<< answersFor c.english

type Adoption =
  { progress :: Progress
  -- | Whether anything had to be placed by rank, which is to say the payload
  -- | predates v5 and is worth rewriting in the current shape.
  , migrated :: Boolean
  -- | Whether that placement can be believed. False only when there were ranks
  -- | to place *and* the deck has moved since they were written.
  , sound :: Boolean
  }

-- | Resolve a decoded payload onto this deck.
-- |
-- | v5 entries name their card by slug, which means the same word in every
-- | version of the deck, so there is nothing to resolve and nothing that can go
-- | wrong. Older entries name it by rank — a position — and turning a position
-- | back into a word is only sound while the deck has not moved since. That is
-- | precisely what the fingerprint attests, so it is required for those and
-- | irrelevant for the rest: the fingerprint's last act is to certify its own
-- | retirement.
-- |
-- | A slug that is not in the deck is kept. It costs a few bytes, everything
-- | that reads progress walks the deck rather than the history, and a backup
-- | restored onto a stale bundle would otherwise quietly lose the newest words.
-- | A rank that is not in the deck can only be dropped — there is no word to
-- | attach it to.
adopt :: String -> Index -> Saved -> Adoption
adopt fingerprint idx saved =
  { progress: Progress.fromEntries $ Array.mapMaybe place saved.cards
  , migrated
  , sound: not migrated || knownDeck
  }
  where
    migrated = Array.any (\c -> c.slug == Nothing) saved.cards

    -- v1 carried no fingerprint and predates every renumbering, so an absent
    -- one is as good as a match.
    knownDeck = saved.deck == Nothing || saved.deck == Just fingerprint

    place c = case c.slug of
      Just slug -> Just $ slug /\ c.progress
      Nothing -> do
        rank <- c.rank
        found <- Map.lookup rank idx.byRank
        pure $ found.slug /\ c.progress

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
  { progress: Progress.mapWithSlug fix progress
  , demoted: Array.length $ Array.filter stranded $ Progress.entries progress
  }
  where
    ineligible :: Slug -> CardProgress -> Boolean
    ineligible slug cp = case card slug idx of
      Just c -> cp.direction == Production && not (isCanonical c idx)
      Nothing -> false

    stranded :: Slug /\ CardProgress -> Boolean
    stranded pair = ineligible (fst pair) (snd pair)

    fix slug cp =
      if ineligible slug cp then cp { direction = Recognition, box = graduationBox }
      else cp
