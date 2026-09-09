-- | What the study screen is, as distinct from what it does.
-- |
-- | One `State` and one `Message` for the whole screen, rather than a
-- | component per sheet. The sheets have no state of their own worth speaking
-- | of — the progress sheet has none at all — and what they do is change the
-- | screen's progress or raise a notice. Nesting them would buy a boundary
-- | that has to be undone at every crossing.
module Flashcards.Pages.Study.Model
  ( Message(..)
  , Purpose(..)
  , Screen(..)
  , Session
  , State
  , Summary
  , Undo
  , noticing
  , untouched
  )
  where

import Prelude

import Data.DateTime.Instant (Instant)
import Data.Maybe (Maybe(..))
import Effect.Aff (Milliseconds(..), delay)
import Elmish (Transition, fork)
import Flashcards.Accent as Accent
import Flashcards.Deck as DeckIndex
import Flashcards.Language (Language)
import Flashcards.Sync as Sync
import Flashcards.Types.Card (Slug)
import Flashcards.Types.Grade (Grade)
import Flashcards.Types.Progress (Progress)

-- | Why a session exists, which is also whether its answers outlive it.
-- |
-- | A `Drill` is chosen, not scheduled. Getting a word right thirty seconds
-- | after reading it off a list of your worst words is not evidence you will
-- | have it next week, and letting it promote a box would push the review out
-- | on the strength of exactly the massed practice spacing exists to avoid.
-- | So a drill writes nothing at all — not the box, not the tallies.
-- |
-- | Not even `seen`, which is the one that would be tempting: it is what
-- | `Progress.merge` uses to decide which of two devices is further along, so
-- | a drill that raised it could make practice on this device overwrite a real
-- | review from another.
data Purpose
  = Review
  | Drill

derive instance Eq Purpose

instance Show Purpose where
  show Review = "Review"
  show Drill = "Drill"

type Session =
  { purpose :: Purpose
  , queue :: Array Slug
  , position :: Int
  , flipped :: Boolean
  , gotIt :: Int
  , again :: Int
  }

type Summary =
  { answered :: Int
  , gotIt :: Int
  , again :: Int
  -- | When the session ended, so "next review in ..." has something to count
  -- | from without the view needing a clock.
  , at :: Instant
  }

-- | The whole of one step backwards. The progress is kept entire rather than
-- | as the one card that changed: `applyGrade` is the only thing that knows
-- | what a grade touches, and re-deriving that here is how the two drift.
type Undo =
  { progress :: Progress
  , screen :: Screen
  }

data Screen
  = Loading
  | Studying Session
  | Complete Summary

type State =
  { progress :: Progress
  , screen :: Screen
  -- | `Just` the moment the panel was opened, which doubles as "is it open".
  -- | Fixed at open, like the progress sheet, so "last synced 3 days ago" does
  -- | not tick over while you are reading it.
  , panel :: Maybe Instant
  , notice :: Maybe String
  , canSpeak :: Boolean
  -- | Every voice the device has, and the slice belonging to the language
  -- | being studied. Keeping both means switching re-filters rather than
  -- | re-subscribing.
  , allVoices :: Array Accent.Voice
  , voices :: Array Accent.Voice
  , accent :: Maybe String
  , voice :: Maybe String
  , savedAccent :: Maybe String
  , savedVoice :: Maybe String
  , language :: Language
  -- | This device's sync key. `Nothing` only for the moment before startup
  -- | finishes; after that it is always set, generated on first run.
  , syncKey :: Maybe String
  , index :: DeckIndex.Index
  -- | `Just` the moment the screen was opened, which doubles as "is it open".
  -- | The time is fixed at open so the due counts cannot shift underneath you.
  , statsAt :: Maybe Instant
  , pairing :: Boolean
  , canShare :: Boolean
  , canScan :: Boolean
  , scanning :: Boolean
  -- | What the server is known to hold, and when it last took something.
  -- |
  -- | `sent` is the progress itself rather than a flag, so "is there anything
  -- | to send" is answered by comparison and cannot drift out of step with
  -- | reality the way a flag set in the wrong place would. `Nothing` means
  -- | this device has not exchanged anything yet *this run* and so does not
  -- | know — which is different from knowing there is something to send.
  -- | Enough to put the last grade back, and only the last one.
  -- |
  -- | Cleared as soon as the progress reaches the server, because undoing
  -- | after that would lose the argument anyway: the next merge sees a higher
  -- | `seen` on the other side and takes it, silently re-applying the grade.
  -- | Better to stop offering it than to offer something that quietly fails.
  , undo :: Maybe Undo
  , sent :: Maybe Progress
  , syncedAt :: Maybe Instant
  , offline :: Boolean
  -- | Where this app is served from, so the pairing link is absolute and can
  -- | be pasted anywhere rather than only followed from here.
  , origin :: String
  }

data Message
  = Loaded
      { progress :: Progress
      , now :: Instant
      , canSpeak :: Boolean
      , savedAccent :: Maybe String
      , savedVoice :: Maybe String
      , language :: Language
      -- | Carried rather than rebuilt, because loading progress needs it too:
      -- | anything written before v5 names its cards by position, and only the
      -- | deck can say which word that was.
      , index :: DeckIndex.Index
      , syncKey :: String
      , origin :: String
      , syncedAt :: Maybe Instant
      , canShare :: Boolean
      , canScan :: Boolean
      }
  | Flip
  | Answer Grade
  | Answered Grade Instant
  | Undo
  | StartAnother
  | StartedAnother Instant
  | TogglePanel
  | OpenedPanel Instant
  | DismissNotice
  | SpeakCurrent
  | ChooseAccent String
  | ChooseLanguage String
  | VoicesAvailable (Array Accent.Voice)
  | CycleVoice
  | DrillLeeches
  | ShowStats
  | StatsAt Instant
  | HideStats
  -- | Ask the other side for its bytes. Safe to send at any time: the merge
  -- | is order-insensitive, so a sync that overlaps another loses nothing.
  | Sync
  -- | Carries the language it was fetched for. A request in flight outlives a
  -- | switch, and applying a Spanish answer to a German session would merge
  -- | one deck's history into the other's key.
  | Synced String Sync.Remote
  -- | Carries what was sent, so `sent` records the exact progress the server
  -- | is now known to hold rather than whatever state has drifted to since.
  | Pushed Progress Boolean
  | SyncedAt Instant
  | ShowPairing
  | HidePairing
  | CopyLink
  | Copied String
  | ShareLink
  -- | Reading the paste field is an effect, so it takes two hops, the way
  -- | grading does for the clock.
  | UseLink
  | LinkPasted String
  | StartScan
  | Scanned Sync.Scan
  | StopScan

-- | Whether a session can be rebuilt under the reader without costing them
-- | anything: nothing answered into it, and no card turned over. A session
-- | with answers in it has a place worth keeping, and a flipped card is an
-- | answer someone is looking at.
-- |
-- | Never a drill. Rebuilding one would quietly swap the words you asked for
-- | with whatever happens to be due, and a drill's queue is the whole point
-- | of it.
untouched :: Screen -> Boolean
untouched = case _ of
  Studying session ->
    session.purpose == Review && session.position == 0 && not session.flipped
  _ -> false

noticing :: State -> String -> Transition Message State
noticing state message = do
  fork do
    delay $ Milliseconds 3500.0
    pure DismissNotice
  pure state { notice = Just message }
