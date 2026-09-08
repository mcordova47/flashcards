-- | Reading and writing the progress file. The bytes are identical to what
-- | lives in localStorage — see `Flashcards.Types.Progress`.
module Flashcards.Backup
  ( download
  , filename
  , parse
  , pickFile
  , serialize
  )
  where

import Prelude

import Data.Argonaut.Core (stringify)
import Data.Argonaut.Parser (jsonParser)
import Data.Bifunctor (lmap)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Uncurried (EffectFn1, EffectFn2, mkEffectFn1, runEffectFn1, runEffectFn2)
import Flashcards.Deck (Index)
import Flashcards.Deck as Deck
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress

-- | Stable rather than dated, so saving into a synced folder overwrites the
-- | previous copy instead of piling up.
filename :: String
filename = "palabras-progress.json"

serialize :: String -> String -> Progress -> String
serialize language deck = stringify <<< Progress.toJson language deck

-- | Import combines two histories, and placing one wrongly would attach it to
-- | the wrong words with no visible symptom, so anything unsound is refused
-- | outright rather than warned about.
-- |
-- | Since v5 that almost never happens: a file that names its cards by slug is
-- | placeable on any version of the deck, which is the whole point. Only an
-- | older file, written against a deck that has since moved, has to be turned
-- | away. See `Flashcards.Deck.adopt`.
-- |
-- | The wrong language is refused outright. From v5 the file says which one it
-- | is; before that the fingerprint gives the same answer, since no two decks
-- | share one — and a v1 file, which carries neither, predates the second deck
-- | by long enough that none can exist.
parse :: String -> String -> Index -> String -> Either String Progress
parse language deck idx raw = do
  json <- lmap (const "That file isn't valid JSON.") $ jsonParser raw
  saved <- lmap (const "That file isn't a Palabras backup.") $ Progress.fromJson json
  case saved.language of
    Just other | other /= language -> Left "That backup is for a different language."
    _ -> do
      let adopted = Deck.adopt deck idx saved
      if adopted.sound then Right adopted.progress
      else Left "That backup predates a deck change, so its words can't be matched up."

download :: String -> String -> Effect Unit
download = runEffectFn2 download_

pickFile :: (String -> Effect Unit) -> Effect Unit
pickFile handler = runEffectFn1 pickFile_ $ mkEffectFn1 handler

foreign import download_ :: EffectFn2 String String Unit

foreign import pickFile_ :: EffectFn1 (EffectFn1 String Unit) Unit
