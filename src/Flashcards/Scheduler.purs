-- | The whole of the app's learning logic, as total functions of their inputs.
-- | No `Effect`, no storage, no clock of its own — the caller passes the time
-- | in. This is the file to rewrite when Leitner gets replaced by SM-2 or FSRS.
module Flashcards.Scheduler
  ( applyGrade
  , buildSession
  , intervalFor
  , maxBox
  , requeue
  , requeueGap
  , sessionSize
  )
  where

import Prelude

import Data.Array as Array
import Data.DateTime.Instant (Instant, instant, unInstant)
import Data.Maybe (Maybe, fromMaybe, isNothing)
import Data.Newtype (unwrap)
import Data.Time.Duration (Milliseconds(..))
import Flashcards.Types.Card (Card, Rank)
import Flashcards.Types.Grade (Grade(..))
import Flashcards.Types.Progress (CardProgress, Progress)
import Flashcards.Types.Progress as Progress

-- | Short enough to finish on a train platform. A session that ends is a
-- | session you come back to.
sessionSize :: Int
sessionSize = 20

-- | How far ahead a missed card is reinserted into the current session.
requeueGap :: Int
requeueGap = 5

maxBox :: Int
maxBox = 5

-- | Box 0 is due immediately, so a missed card reappears in the same session.
intervalFor :: Int -> Milliseconds
intervalFor box = Milliseconds $ day * case box of
  1 -> 1.0
  2 -> 3.0
  3 -> 7.0
  4 -> 21.0
  5 -> 60.0
  _ -> 0.0
  where
    day = 86400000.0

-- | Due reviews first, most overdue first; then brand-new words in frequency
-- | order. The deck is never shuffled — its order *is* the curriculum, so the
-- | next new word is always the most common one you do not yet know.
buildSession :: Array Card -> Progress -> Instant -> Int -> Array Rank
buildSession deck progress now size =
  Array.take size $ map _.rank dueCards <> map _.rank newCards
  where
    annotated = deck <#> \card -> { rank: card.rank, state: Progress.lookup card.rank progress }

    dueCards =
      annotated
        # Array.mapMaybe (\a -> a.state <#> \s -> { rank: a.rank, due: s.due })
        # Array.filter (\a -> a.due <= now)
        # Array.sortWith _.due

    newCards = Array.filter (isNothing <<< _.state) annotated

-- | `Again` drops a card to box 0, due now, so it comes round again before the
-- | session ends. `GotIt` promotes it one box and pushes the next review out.
applyGrade :: Grade -> Instant -> Maybe CardProgress -> CardProgress
applyGrade grade now previous =
  { box, due: addInterval now $ intervalFor box, seen: prev.seen + 1, lapses }
  where
    prev = fromMaybe { box: 0, due: now, seen: 0, lapses: 0 } previous

    box = case grade of
      Again -> 0
      GotIt -> min maxBox $ prev.box + 1

    -- Forgetting a word you had never learned is not a lapse.
    lapses = case grade of
      Again | prev.box > 0 -> prev.lapses + 1
      _ -> prev.lapses

-- | Put a missed card back into the queue a few positions later, so the loop
-- | closes before the session ends. Lands at the end if there is no room left.
requeue :: Rank -> Int -> Array Rank -> Array Rank
requeue rank position queue =
  fromMaybe (Array.snoc queue rank) $ Array.insertAt target rank queue
  where
    target = min (position + requeueGap) (Array.length queue)

addInterval :: Instant -> Milliseconds -> Instant
addInterval t (Milliseconds ms) =
  fromMaybe t $ instant $ Milliseconds $ unwrap (unInstant t) + ms
