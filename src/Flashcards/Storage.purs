-- | The only place the app touches the outside world's memory. Corrupt or
-- | future-versioned data starts you over rather than crashing — losing a
-- | streak beats a white screen.
module Flashcards.Storage
  ( accentKey
  , languageKey
  , load
  , loadAccent
  , loadLanguage
  , loadVoice
  , progressKey
  , save
  , saveAccent
  , saveLanguage
  , saveVoice
  , voiceKey
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

-- | Keyed by language and schema version from day one, which is why adding a
-- | second deck needed no migration: it is simply a different key.
progressKey :: String -> String
progressKey code = "flashcards." <> code <> ".v1"

-- | Deliberately its own key rather than a field in the progress blob. Which
-- | voices exist is a property of the device, not of the learner, so this must
-- | never travel in a backup file or a future sync — your phone and your
-- | laptop can reasonably disagree about it.
accentKey :: String -> String
accentKey code = "flashcards." <> code <> ".accent"

-- | Same reasoning as `accentKey`, and more so: a voice name that exists on
-- | one machine may be missing — or listed but broken — on another.
voiceKey :: String -> String
voiceKey code = "flashcards." <> code <> ".voice"

-- | Takes the current deck fingerprint so it can tell you when your saved
-- | progress predates a deck change. It loads anyway: this is your own history
-- | on your own device, and refusing it would be worse than the drift. Import
-- | applies the stricter rule — see `Flashcards.Backup`.
load :: String -> String -> Effect Progress
load code deck = do
  storage <- localStorage =<< window
  Storage.getItem (progressKey code) storage >>= case _ of
    Nothing -> pure Progress.empty
    Just raw -> case jsonParser raw of
      Left err -> recover $ "saved progress is not valid JSON: " <> err
      Right json -> case Progress.fromJson json of
        Left err -> recover $ "saved progress could not be read: " <> printJsonDecodeError err
        Right saved -> do
          when (saved.deck /= Nothing && saved.deck /= Just deck) $
            Console.warn "saved progress was written against a different deck; ranks may have shifted"
          pure saved.progress
  where
    recover message = do
      Console.warn $ message <> " — starting fresh"
      pure Progress.empty

save :: String -> String -> Progress -> Effect Unit
save code deck progress = do
  storage <- localStorage =<< window
  Storage.setItem (progressKey code) (stringify $ Progress.toJson deck progress) storage

loadAccent :: String -> Effect (Maybe String)
loadAccent code = do
  storage <- localStorage =<< window
  Storage.getItem (accentKey code) storage

saveAccent :: String -> String -> Effect Unit
saveAccent code accent = do
  storage <- localStorage =<< window
  Storage.setItem (accentKey code) accent storage

loadVoice :: String -> Effect (Maybe String)
loadVoice code = do
  storage <- localStorage =<< window
  Storage.getItem (voiceKey code) storage

saveVoice :: String -> String -> Effect Unit
saveVoice code voice = do
  storage <- localStorage =<< window
  Storage.setItem (voiceKey code) voice storage

-- | Which language is being studied. Not per-language, obviously, and kept
-- | apart from progress so switching never risks the histories.
languageKey :: String
languageKey = "flashcards.language"

loadLanguage :: Effect (Maybe String)
loadLanguage = do
  storage <- localStorage =<< window
  Storage.getItem languageKey storage

saveLanguage :: String -> Effect Unit
saveLanguage code = do
  storage <- localStorage =<< window
  Storage.setItem languageKey code storage
