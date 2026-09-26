-- | What the verb drills are, as distinct from what they do.
module Flashcards.Pages.Verbs.Model
  ( Message(..)
  , Phase(..)
  , State
  , namespace
  )
  where

import Prelude

import Data.DateTime.Instant (Instant)
import Data.Maybe (Maybe)
import Flashcards.Exercise (Exercise, Verdict)
import Flashcards.Sync as Sync
import Flashcards.Types.Card (Slug)
import Flashcards.Types.Grade (Grade)
import Flashcards.Types.Progress (Progress)

-- | Its own namespace, so its progress is its own blob on the server and its
-- | own key in storage — `flashcards.verbs.v1` beside `flashcards.es.v1`, via
-- | `Storage.progressKey`, rather than a second place that spells the key out. The *pairing* key is shared, so a device paired for
-- | the flashcards is already paired for this — one key, both pages.
namespace :: String
namespace = "verbs"

type State =
  { progress :: Progress
  -- | What is left of the session, the item being asked first.
  , queue :: Array Slug
  -- | Which of the first item's pool is being asked. Held rather than
  -- | recomputed, because grading moves `seen` and `Exercise.pick` would then
  -- | change the question under the answer.
  , shown :: Maybe Exercise
  -- | This session's tally. Their sum is how many have been graded, and
  -- | until that is zero a sync bringing history in can rebuild the session
  -- | without taking anything back off the screen.
  , got :: Int
  , again :: Int
  , typed :: String
  -- | How far the current question has got.
  , phase :: Phase
  , syncKey :: Maybe String
  -- | What the server is known to hold. See the study page, where the same
  -- | comparison decides whether the panel may claim to be up to date.
  , sent :: Maybe Progress
  , offline :: Boolean
  , loaded :: Boolean
  }

-- | Where the current question has got to.
-- |
-- | One field rather than a flag each, because the two kinds of answer end
-- | differently — a typed one is graded by the comparison, a self-graded one
-- | by the reader — and two booleans would have to be kept agreeing.
data Phase
  -- | Waiting: for something typed, or for a tap to reveal.
  = Asked
  -- | Typed and compared, and the grade followed from that.
  | Compared Verdict
  -- | Revealed, and waiting for the reader to say how it went.
  | Revealed
  -- | Self-graded, and the grade on its way to `Graded`. Here so that a
  -- | second tap on *Again* or *Got it* cannot grade twice — the typed side
  -- | gets that from `Compared`, which it reaches immediately; this side has
  -- | to wait for the clock, and would otherwise stay tappable meanwhile.
  | Judging

derive instance Eq Phase

data Message
  = Loaded { progress :: Progress, syncKey :: Maybe String }
  | Started Instant
  | Typed String
  -- | Check what was typed, or reveal what a self-graded answer was.
  | Answer
  -- | How the reader says they did, where nothing can check it for them.
  | Judge Grade
  | Graded Grade Instant
  | Next
  | Sync
  | Synced Sync.Remote
  | Pushed Progress Boolean
