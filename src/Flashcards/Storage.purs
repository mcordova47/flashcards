-- | The only place the app touches the outside world's memory. Corrupt or
-- | future-versioned data starts you over rather than crashing — losing a
-- | streak beats a white screen.
module Flashcards.Storage
  ( accentKey
  , appendNote
  , languageKey
  , readNotes
  , notesKey
  , forgetNotesSent
  , loadNotesSent
  , markNotesSent
  , notesSentKey
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
import Data.Array as Array
import Data.Bifunctor (lmap)
import Data.Argonaut.Decode.Error (printJsonDecodeError)
import Data.Argonaut.Parser (jsonParser)
import Data.DateTime.Instant (Instant, instant, unInstant)
import Data.Either (Either(..))
import Data.Int as Int
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Data.Number as Number
import Data.Time.Duration (Milliseconds(..))
import Effect (Effect)
import Effect.Class.Console as Console
import Flashcards.Notes (Note)
import Flashcards.Notes as Notes
import Flashcards.Payload as Payload
import Flashcards.Types.Card (Rank, Slug)
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress
import Web.HTML (window)
import Web.HTML.Window (localStorage)
import Web.Storage.Storage as Storage

-- | Keyed by namespace and schema version from day one, which is why adding a
-- | second deck needed no migration, and why a second *page* needs none
-- | either: each is simply a different key. `es`, `de`, `verbs`.
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

-- | Takes a way to turn a rank into a slug, because progress written before v5
-- | names its cards by position and only the deck can say which word stood
-- | there. A function rather than a deck, so this module does not have to know
-- | what a card is — see `Flashcards.Payload.adopt`.
-- |
-- | It loads even when the fingerprint says that placement is unreliable: this
-- | is your own history on your own device, and it is what the app has been
-- | showing you all along, so discarding it now would be a loss and not a fix.
-- | Import applies the stricter rule — see `Flashcards.Backup`.
load :: String -> String -> (Rank -> Maybe Slug) -> Effect Progress
load code deck slugAt = do
  storage <- localStorage =<< window
  Storage.getItem (progressKey code) storage >>= case _ of
    Nothing -> pure Progress.empty
    Just raw -> case jsonParser raw of
      Left err -> recover $ "saved progress is not valid JSON: " <> err
      Right json -> case Progress.fromJson json of
        Left err -> recover $ "saved progress could not be read: " <> printJsonDecodeError err
        Right saved -> do
          let adopted = Payload.adopt deck slugAt saved
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

-- | Every note written on this device, from either page. One key for the
-- | whole app rather than one per page, since the list is read as one. See
-- | `Flashcards.Notes`.
notesKey :: String
notesKey = "flashcards.notes.v1"

-- | `Nothing` when there are notes stored and this build cannot read them —
-- | which is not the same as there being none, and must not be treated as it.
-- | Progress can afford to start over on unreadable data, because it also
-- | lives on the server; notes live only here.
readNotes :: Effect (Maybe (Array Note))
readNotes = do
  storage <- localStorage =<< window
  Storage.getItem notesKey storage >>= case _ of
    Nothing -> pure $ Just []
    Just raw -> case Notes.fromJson =<< lmap (const Notes.unreadable) (jsonParser raw) of
      Right notes -> pure $ Just notes
      Left err -> do
        Console.warn $ "saved notes could not be read: " <> printJsonDecodeError err
        pure Nothing

-- | Read, add and write in one go rather than writing back a list held in
-- | state: the other page may be open in another tab, and a list read when
-- | this sheet opened would quietly drop whatever that one wrote since.
-- |
-- | Refuses, and writes nothing, when what is stored cannot be read. The case
-- | that bites is a tab left open across the deploy that moves notes to a new
-- | version: written over by this code, every note the newer one kept would
-- | be gone for good.
appendNote :: Note -> Effect (Maybe (Array Note))
appendNote n = readNotes >>= case _ of
  Nothing -> pure Nothing
  Just stored -> do
    let notes = Array.snoc stored n
    storage <- localStorage =<< window
    Storage.setItem notesKey (stringify $ Notes.toJson notes) storage
    pure $ Just notes

-- | How many of this device's notes have reached the server. See
-- | `Notes.undelivered`. Beside the notes rather than inside their blob, so
-- | that the saved format — which a newer app may already have moved past —
-- | is left exactly as it was.
notesSentKey :: String
notesSentKey = "flashcards.notes.sent.v1"

-- | Zero when there is nothing readable stored, which sends everything: the
-- | safe way to be wrong, since the server stores each note once.
loadNotesSent :: Effect Int
loadNotesSent = do
  storage <- localStorage =<< window
  raw <- Storage.getItem notesSentKey storage
  pure case Int.fromString =<< raw of
    Just n | n >= 0 -> n
    _ -> 0

-- | Never lowers it. Two tabs can each deliver and answer out of order, and
-- | the one that knew fewer notes must not undo the one that knew more.
markNotesSent :: Int -> Effect Unit
markNotesSent n = do
  sent <- loadNotesSent
  when (n > sent) do
    storage <- localStorage =<< window
    Storage.setItem notesSentKey (show n) storage

forgetNotesSent :: Effect Unit
forgetNotesSent = do
  storage <- localStorage =<< window
  Storage.removeItem notesSentKey storage
