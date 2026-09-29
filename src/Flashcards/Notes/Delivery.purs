-- | Getting this device's notes to someone who can act on them. See #62.
-- |
-- | Fire and forget, like the rest of sync: a note that does not go now goes
-- | the next time anything syncs, and nothing on screen waits for it. It is
-- | tried when a note is saved, so one written online arrives straight away,
-- | and whenever a page syncs, so one written offline follows it up.
module Flashcards.Notes.Delivery
  ( deliver
  )
  where

import Prelude

import Data.Argonaut.Core (stringify)
import Data.Array as Array
import Data.Foldable (for_)
import Effect (Effect)
import Flashcards.Notes as Notes
import Flashcards.Storage as Storage
import Flashcards.Sync as Sync

-- | Sends whatever has not been delivered, and on success remembers that it
-- | has. Nothing when there is no key yet, or when the stored notes cannot be
-- | read — a list this build does not understand is not one to send.
-- |
-- | What is remembered is the length of the list that was read, not of what
-- | is stored by the time the answer comes: a note saved meanwhile was not in
-- | the request, and counting it would mean it never goes.
deliver :: Effect Unit
deliver =
  Sync.loadKey >>= flip for_ \key ->
    Storage.readNotes >>= flip for_ \notes -> do
      sent <- Storage.loadNotesSent
      -- Counted against a list that is no longer here. Forgotten, or it
      -- would stay above the list's length for ever, since it never lowers.
      when (sent > Array.length notes) Storage.forgetNotesSent
      let fresh = Notes.undelivered sent notes
      unless (Array.null fresh) $
        Sync.pushNotes key (stringify $ Notes.toJson fresh) \ok ->
          when ok $ Storage.markNotesSent $ Array.length notes
