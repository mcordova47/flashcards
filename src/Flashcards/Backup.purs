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
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress

-- | Stable rather than dated, so saving into a synced folder overwrites the
-- | previous copy instead of piling up.
filename :: String
filename = "palabras-progress.json"

serialize :: String -> Progress -> String
serialize deck = stringify <<< Progress.toJson deck

-- | Import combines two histories, and getting the deck wrong would remap
-- | progress onto the wrong words with no visible symptom — so a fingerprint
-- | mismatch is refused outright. A v1 file carries no fingerprint and predates
-- | any renumbering, so it is accepted.
parse :: String -> String -> Either String Progress
parse deck raw = do
  json <- lmap (const "That file isn't valid JSON.") $ jsonParser raw
  saved <- lmap (const "That file isn't a Palabras backup.") $ Progress.fromJson json
  case saved.deck of
    Just other | other /= deck -> Left "That backup was made against a different deck."
    _ -> Right saved.progress

download :: String -> String -> Effect Unit
download = runEffectFn2 download_

pickFile :: (String -> Effect Unit) -> Effect Unit
pickFile handler = runEffectFn1 pickFile_ $ mkEffectFn1 handler

foreign import download_ :: EffectFn2 String String Unit

foreign import pickFile_ :: EffectFn1 (EffectFn1 String Unit) Unit
