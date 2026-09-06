-- | Everything the progress screen shows, as pure functions of the deck, the
-- | saved progress, and the current time. No `Effect`, no formatting, no view
-- | concerns — the screen renders what this returns.
module Flashcards.Stats
  ( Band
  , Counts
  , Leech
  , Mastery(..)
  , Overview
  , bandSize
  , bands
  , describeDuration
  , leechThreshold
  , leeches
  , masteryOf
  , nextDueIn
  , overview
  )
  where

import Prelude

import Control.Alternative (guard)
import Data.Array as Array
import Data.DateTime.Instant (Instant, instant, unInstant)
import Data.Foldable (minimum, sum)
import Data.Int as Int
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Newtype (unwrap)
import Data.Time.Duration (Milliseconds(..))
import Flashcards.Scheduler (maxBox)
import Flashcards.Types.Card (Card, Rank, rankToInt)
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Progress (CardProgress, Progress)
import Flashcards.Types.Progress as Progress

-- | Four buckets rather than six boxes: the boxes are a scheduling detail, and
-- | a stacked bar with six segments reads as noise.
data Mastery
  = Unseen
  | Learning
  | Familiar
  | Mastered

derive instance Eq Mastery

instance Show Mastery where
  show Unseen = "Unseen"
  show Learning = "Learning"
  show Familiar = "Familiar"
  show Mastered = "Mastered"

type Counts =
  { unseen :: Int
  , learning :: Int
  , familiar :: Int
  , mastered :: Int
  }

type Band =
  { from :: Int
  , to :: Int
  , counts :: Counts
  }

type Overview =
  { seen :: Int
  , total :: Int
  , mastered :: Int
  , answers :: Int
  , misses :: Int
  -- | Percentage right. `Nothing` until there is something to divide, rather
  -- | than a meaningless 0% or 100% on an untouched deck.
  , accuracy :: Maybe Number
  , dueNow :: Int
  , dueTomorrow :: Int
  -- | How many words have graduated to being asked English to Spanish.
  , producing :: Int
  }

type Leech =
  { rank :: Rank
  , word :: String
  , english :: String
  , lapses :: Int
  }

-- | One bar per hundred words. Fine enough to show the frontier moving,
-- | coarse enough to fit on a phone.
bandSize :: Int
bandSize = 100

-- | Three failures after you had already learned a word is enough to call it a
-- | leech; below that it is ordinary forgetting.
leechThreshold :: Int
leechThreshold = 3

-- | Direction matters as much as box here. A card in production box 1 knows
-- | more than one in recognition box 3, so ranking on box alone would order
-- | them backwards. "Mastered" means you can produce the word, which is the
-- | only sense in which you really know it.
masteryOf :: Maybe CardProgress -> Mastery
masteryOf = case _ of
  Nothing -> Unseen
  Just cp -> case cp.direction of
    -- A graduating card leaves recognition at box 3, so only a card barred
    -- from production can be up here: this is as far as it can go, and that
    -- is what mastery means for it.
    Recognition
      | cp.box >= maxBox -> Mastered
      | cp.box >= 2 -> Familiar
      | otherwise -> Learning
    Production
      | cp.box >= 3 -> Mastered
      | otherwise -> Familiar

tally :: Progress -> Array Card -> Counts
tally progress = Array.foldl add { unseen: 0, learning: 0, familiar: 0, mastered: 0 }
  where
    add acc card = case masteryOf $ Progress.lookup card.rank progress of
      Unseen -> acc { unseen = acc.unseen + 1 }
      Learning -> acc { learning = acc.learning + 1 }
      Familiar -> acc { familiar = acc.familiar + 1 }
      Mastered -> acc { mastered = acc.mastered + 1 }

-- | The deck sliced into frequency bands. Because the deck is ordered by
-- | frequency, the shape of this is the story: a solid left edge decaying
-- | rightwards, with the boundary marking how far you have got.
bands :: Int -> Array Card -> Progress -> Array Band
bands size deck progress =
  Array.range 0 (count - 1) <#> \i ->
    let
      from = i * size + 1
      to = from + size - 1
    in
      { from
      , to: min to total
      , counts: tally progress $ Array.filter (within from to) deck
      }
  where
    total = Array.length deck
    count = max 1 $ (total + size - 1) / size
    within from to card = rankToInt card.rank >= from && rankToInt card.rank <= to

overview :: Instant -> Array Card -> Progress -> Overview
overview now deck progress =
  { seen: Array.length tracked
  , total: Array.length deck
  , mastered: Array.length $ Array.filter (\cp -> masteryOf (Just cp) == Mastered) tracked
  , answers
  , misses
  , accuracy:
      if answers == 0 then Nothing
      else Just $ 100.0 * Int.toNumber (answers - misses) / Int.toNumber answers
  , dueNow: Array.length $ Array.filter (\cp -> cp.due <= now) tracked
  , dueTomorrow: Array.length $ Array.filter (\cp -> cp.due > now && cp.due <= tomorrow) tracked
  , producing: Array.length $ Array.filter (\cp -> cp.direction == Production) tracked
  }
  where
    -- Only cards still in the deck count, so a resynced deck cannot leave
    -- orphaned history inflating the totals.
    tracked = Array.mapMaybe (\card -> Progress.lookup card.rank progress) deck
    answers = sum $ map _.seen tracked
    misses = sum $ map _.missed tracked
    tomorrow = plusDays 1.0 now

-- | Words that keep slipping *after* you had learned them.
-- |
-- | `lapses` is the right measure here and `missed` is not: struggling with a
-- | brand-new word is just learning, whereas forgetting one you had already
-- | earned is the thing worth surfacing.
leeches :: Int -> Array Card -> Progress -> Array Leech
leeches threshold deck progress =
  Array.sortBy mostLapsedFirst $ Array.mapMaybe toLeech deck
  where
    toLeech card = do
      cp <- Progress.lookup card.rank progress
      guard $ cp.lapses >= threshold
      pure { rank: card.rank, word: card.word, english: card.english, lapses: cp.lapses }

    -- Stable sort, so equal counts stay in frequency order.
    mostLapsedFirst a b = compare b.lapses a.lapses

-- | How long until the soonest card falls due. `Nothing` when nothing is
-- | scheduled ahead at all — an untouched deck, or one where everything is
-- | already waiting for you.
nextDueIn :: Instant -> Array Card -> Progress -> Maybe Milliseconds
nextDueIn now deck progress = do
  soonest <- minimum $ Array.filter (_ > now) $ map _.due tracked
  pure $ Milliseconds $ unwrap (unInstant soonest) - unwrap (unInstant now)
  where
    tracked = Array.mapMaybe (\card -> Progress.lookup card.rank progress) deck

-- | A wait in round human units — "4 hours", "1 day". Deliberately coarse:
-- | the exact minute is noise when the answer is "come back this evening".
-- |
-- | Each unit is chosen from its own rounded value, so 59.7 minutes reads as
-- | "1 hour" rather than "60 minutes", and 23.8 hours as "1 day".
describeDuration :: Milliseconds -> String
describeDuration (Milliseconds ms) =
  -- A `let` rather than guards with a `where`: PureScript does not bring
  -- `where` bindings into scope inside guard expressions.
  let
    minutes = Int.round $ ms / 60000.0
    hours = Int.round $ ms / 3600000.0
    days = Int.round $ ms / 86400000.0
    plural n unit = show n <> " " <> unit <> (if n == 1 then "" else "s")
  in
    if ms < 60000.0 then "under a minute"
    else if minutes < 60 then plural minutes "minute"
    else if hours < 24 then plural hours "hour"
    else plural days "day"

plusDays :: Number -> Instant -> Instant
plusDays days t =
  fromMaybe t $ instant $ Milliseconds $ unwrap (unInstant t) + days * 86400000.0
