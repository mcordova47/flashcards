-- | The bytes progress travels as, and the rules for accepting someone else's.
-- |
-- | Identical to what `Flashcards.Storage` puts in localStorage, so there is
-- | one codec and one validation path rather than two that drift — see
-- | `Flashcards.Types.Progress`.
module Flashcards.Payload
  ( Adoption
  , adopt
  , parse
  , serialize
  )
  where

import Prelude

import Data.Argonaut.Core (stringify)
import Data.Argonaut.Parser (jsonParser)
import Data.Bifunctor (lmap)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Array as Array
import Data.Tuple.Nested ((/\))
import Flashcards.Types.Card (Rank, Slug)
import Flashcards.Types.Progress (Progress, Saved)
import Flashcards.Types.Progress as Progress

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
-- | The resolver is how a rank becomes a slug, and it is a function rather
-- | than a deck so that nothing here has to know what a card is: the
-- | flashcards pass `Deck.slugAt`, and a page with no legacy payloads to place
-- | passes `const Nothing` and is done.
-- |
-- | A slug that is not in the deck is kept. It costs a few bytes, everything
-- | that reads progress walks the deck rather than the history, and a backup
-- | restored onto a stale bundle would otherwise quietly lose the newest words.
-- | A rank that is not in the deck can only be dropped — there is no word to
-- | attach it to.
adopt :: String -> (Rank -> Maybe Slug) -> Saved -> Adoption
adopt fingerprint slugAt saved =
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
        slug <- slugAt rank
        pure $ slug /\ c.progress

serialize :: String -> String -> Progress -> String
serialize language deck = stringify <<< Progress.toJson language deck

-- | Accepting someone else's progress combines two histories, and placing one
-- | wrongly would attach it to the wrong words with no visible symptom, so
-- | anything unsound is refused outright rather than warned about.
-- |
-- | Since v5 that almost never happens: a payload that names its cards by slug
-- | is placeable on any version of the deck, which is the whole point. Only an
-- | older one, written against a deck that has since moved, has to be turned
-- | away. See `Flashcards.Deck.adopt`.
-- |
-- | The wrong language is refused outright. From v5 the payload says which one
-- | it is; before that the fingerprint gives the same answer, since no two
-- | decks share one — and a v1 payload, which carries neither, predates the
-- | second deck by long enough that none can exist.
-- |
-- | The reasons are phrased for a reader because nothing stops a future caller
-- | showing them; today the only one is `Flashcards.Sync`, which stays quiet
-- | and leaves the blob alone.
parse :: String -> String -> (Rank -> Maybe Slug) -> String -> Either String Progress
parse language deck slugAt raw = do
  json <- lmap (const "That isn't valid JSON.") $ jsonParser raw
  saved <- lmap (const "That isn't Palabras progress.") $ Progress.fromJson json
  case saved.language of
    Just other | other /= language -> Left "That progress is for a different language."
    _ -> do
      let adopted = adopt deck slugAt saved
      if adopted.sound then Right adopted.progress
      else Left "That progress predates a deck change, so its words can't be matched up."
