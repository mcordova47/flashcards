-- | What the study screen is, as distinct from what it does.
-- |
-- | One `State` and one `Message` for the whole screen, rather than a
-- | component per sheet. The sheets have no state of their own worth speaking
-- | of — the progress sheet has none at all — and what they do is change the
-- | screen's progress or raise a notice. Nesting them would buy a boundary
-- | that has to be undone at every crossing.
module Flashcards.Pages.Study.Model
  ( Message(..)
  , Modal(..)
  , Purpose(..)
  , Screen(..)
  , Session
  , Startup
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
import Flashcards.Milestone as Milestone
import Flashcards.Notes.Sheet as Notes
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
  -- | Where the deck stood when this session opened, so that what it came to
  -- | is a subtraction rather than something remembered between sessions.
  -- | See `Flashcards.Milestone`.
  , began :: Milestone.Standing
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
  , began :: Milestone.Standing
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
  -- | Whatever is over the card, if anything. See `Modal`.
  , modal :: Maybe Modal
  -- | Not a `Modal`, though it is the other thing that appears over the
  -- | screen: see there.
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
  , canShare :: Boolean
  , canScan :: Boolean
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

-- | What is over the card. One field rather than one per overlay, because only
-- | one is ever open: with a field each, every place that opened one had to
-- | clear the others by hand, and every place that asked whether the card was
-- | covered had to list them all — and listing them one at a time is how the
-- | pairing sheet was missed when the note sheet was guarded (#60).
-- |
-- | The notice is left out on purpose, and would be wrong in here. It sits
-- | over the screen but covers nothing: a toast that swallowed keys, or that
-- | opening a sheet could replace, would take the card away from a reader for
-- | three and a half seconds each time something was merely said. It can also
-- | be raised while a sheet is open — the pairing sheet raises most of them —
-- | which a modal, being one of these, could not be.
-- |
-- | Its own type rather than one shared with the drills, which spell the menu
-- | differently and have no pairing. The pages share no state, and a shared
-- | type would be one more thing to keep both of them agreeing with.
data Modal
  -- | The ••• menu, and the moment it was opened. Fixed at open, like the
  -- | progress sheet, so "last synced 3 days ago" does not tick over while you
  -- | are reading it.
  = Panel Instant
  -- | The progress sheet, and the moment it was opened. Fixed so the due
  -- | counts cannot shift underneath you.
  | Stats Instant
  -- | The pairing sheet. Whether the camera is running belongs to it: closing
  -- | the sheet always stopped the camera too, and nothing else reads it.
  | Pairing { scanning :: Boolean }
  -- | The note being written. See `Flashcards.Notes`.
  | Note Notes.Open

-- | Everything that has to be asked of the outside world before the screen can
-- | exist: what was saved, what this device can do, and the time.
-- |
-- | Gathered under one name because a language switch needs exactly the same
-- | set — see `ChooseLanguage`, which reuses the startup path rather than
-- | assembling a second one that would drift from it.
type Startup =
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

data Message
  = Loaded Startup
  -- | A key, not yet read as anything. See `keyMessage`.
  | Pressed String
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
  | WriteNote
  | Notes Notes.Message

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
