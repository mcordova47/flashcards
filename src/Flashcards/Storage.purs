-- | The only place the app touches the outside world's memory. Corrupt or
-- | future-versioned data starts you over rather than crashing — losing a
-- | streak beats a white screen.
module Flashcards.Storage
  ( accentKey
  , languageKey
  , loadSyncedAt
  , saveSyncedAt
  , syncedAtKey
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
import Data.DateTime.Instant (Instant, instant, unInstant)
import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Data.Number as Number
import Data.Time.Duration (Milliseconds(..))
import Effect (Effect)
import Effect.Class.Console as Console
import Flashcards.Deck (Index)
import Flashcards.Deck as Deck
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

-- | Takes the deck and its fingerprint, because progress written before v5
-- | names its cards by position and only the deck can say which word that was.
-- | See `Flashcards.Deck.adopt`.
-- |
-- | It loads even when the fingerprint says that placement is unreliable: this
-- | is your own history on your own device, and it is what the app has been
-- | showing you all along, so discarding it now would be a loss and not a fix.
-- | Import applies the stricter rule — see `Flashcards.Backup`.
load :: String -> String -> Index -> Effect Progress
load code deck idx = do
  storage <- localStorage =<< window
  Storage.getItem (progressKey code) storage >>= case _ of
    Nothing -> pure Progress.empty
    Just raw -> case jsonParser raw of
      Left err -> recover $ "saved progress is not valid JSON: " <> err
      Right json -> case Progress.fromJson json of
        Left err -> recover $ "saved progress could not be read: " <> printJsonDecodeError err
        Right saved -> do
          let adopted = Deck.adopt deck idx saved
          unless adopted.sound $
            Console.warn "saved progress predates a deck change and is keyed by position; some words may have picked up another's history"
          -- Rewrite it keyed by slug straight away, so this happens once
          -- rather than on every load for the rest of time. That stamps the
          -- current fingerprint over a mismatched one, which is honest enough:
          -- the placement has been made, and no later load can improve on it.
          when adopted.migrated $ save code deck adopted.progress
          pure adopted.progress
  where
    recover message = do
      Console.warn $ message <> " — starting fresh"
      pure Progress.empty

save :: String -> String -> Progress -> Effect Unit
save code deck progress = do
  storage <- localStorage =<< window
  Storage.setItem (progressKey code) (stringify $ Progress.toJson code deck progress) storage

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

-- | When this device last got its progress onto the server, so a device that
-- | has been offline for a week can say so rather than only saying "not
-- | synced". Its own key, like the accent and the voice: it is a fact about
-- | this device, and must not travel in a backup.
syncedAtKey :: String -> String
syncedAtKey code = "flashcards." <> code <> ".synced"

loadSyncedAt :: String -> Effect (Maybe Instant)
loadSyncedAt code = do
  storage <- localStorage =<< window
  raw <- Storage.getItem (syncedAtKey code) storage
  pure $ instant <<< Milliseconds =<< Number.fromString =<< raw

saveSyncedAt :: String -> Instant -> Effect Unit
saveSyncedAt code at = do
  storage <- localStorage =<< window
  Storage.setItem (syncedAtKey code) (show $ unwrap $ unInstant at) storage

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
