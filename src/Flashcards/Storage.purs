-- | The only place the app touches the outside world's memory. Corrupt or
-- | future-versioned data starts you over rather than crashing — losing a
-- | streak beats a white screen.
module Flashcards.Storage
  ( key
  , load
  , save
  )
  where

import Prelude

import Data.Argonaut.Core (stringify)
import Data.Argonaut.Decode.Error (printJsonDecodeError)
import Data.Argonaut.Parser (jsonParser)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Effect (Effect)
import Effect.Class.Console as Console
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress
import Web.HTML (window)
import Web.HTML.Window (localStorage)
import Web.Storage.Storage as Storage

-- | Keyed by language and schema version from day one, so a second deck later
-- | is a new key rather than a migration.
key :: String
key = "flashcards.es.v1"

load :: Effect Progress
load = do
  storage <- localStorage =<< window
  Storage.getItem key storage >>= case _ of
    Nothing -> pure Progress.empty
    Just raw -> case jsonParser raw of
      Left err -> recover $ "saved progress is not valid JSON: " <> err
      Right json -> case Progress.fromJson json of
        Left err -> recover $ "saved progress could not be read: " <> printJsonDecodeError err
        Right progress -> pure progress
  where
    recover message = do
      Console.warn $ message <> " — starting fresh"
      pure Progress.empty

save :: Progress -> Effect Unit
save progress = do
  storage <- localStorage =<< window
  Storage.setItem key (stringify $ Progress.toJson progress) storage
