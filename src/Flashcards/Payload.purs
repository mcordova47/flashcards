-- | The bytes progress travels as, and the rules for accepting someone else's.
-- |
-- | Identical to what `Flashcards.Storage` puts in localStorage, so there is
-- | one codec and one validation path rather than two that drift — see
-- | `Flashcards.Types.Progress`.
module Flashcards.Payload
  ( parse
  , serialize
  )
  where

import Prelude

import Data.Argonaut.Core (stringify)
import Data.Argonaut.Parser (jsonParser)
import Data.Bifunctor (lmap)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Flashcards.Deck (Index)
import Flashcards.Deck as Deck
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress

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
parse :: String -> String -> Index -> String -> Either String Progress
parse language deck idx raw = do
  json <- lmap (const "That isn't valid JSON.") $ jsonParser raw
  saved <- lmap (const "That isn't Palabras progress.") $ Progress.fromJson json
  case saved.language of
    Just other | other /= language -> Left "That progress is for a different language."
    _ -> do
      let adopted = Deck.adopt deck idx saved
      if adopted.sound then Right adopted.progress
      else Left "That progress predates a deck change, so its words can't be matched up."
