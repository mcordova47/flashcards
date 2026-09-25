-- | What the verb drills are, as distinct from what they do.
module Flashcards.Pages.Verbs.Model
  ( Message(..)
  , State
  , namespace
  )
  where

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
  -- | How many have been graded this session. Until one has, a sync that
  -- | brings history in can rebuild the session without taking anything
  -- | back off the screen.
  , answered :: Int
  , typed :: String
  -- | `Nothing` until the answer has been checked.
  , verdict :: Maybe Verdict
  , syncKey :: Maybe String
  -- | What the server is known to hold. See the study page, where the same
  -- | comparison decides whether the panel may claim to be up to date.
  , sent :: Maybe Progress
  , offline :: Boolean
  , loaded :: Boolean
  }

data Message
  = Loaded { progress :: Progress, syncKey :: Maybe String }
  | Started Instant
  | Typed String
  | Answer
  | Graded Grade Instant
  | Next
  | Sync
  | Synced Sync.Remote
  | Pushed Progress Boolean
