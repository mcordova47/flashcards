-- | What a session turned out to be worth, beyond the cards that were in it.
-- |
-- | Pure, and decided by comparing where the deck stood when the session began
-- | with where it stands now. Nothing is remembered between sessions: a
-- | milestone is a crossing, and a crossing is two numbers and a subtraction.
-- | So there is no "already celebrated" flag to keep, nothing extra in the
-- | saved progress, and nothing for the merge to arbitrate when two devices
-- | both think they got there first.
module Flashcards.Milestone
  ( Fanfare(..)
  , Milestone(..)
  , Standing
  , describe
  , fanfare
  , reached
  )
  where

import Prelude

import Data.Maybe (Maybe(..))

-- | Where the deck stands: how many words are mastered, how many have been
-- | met at all, and how many there are.
type Standing =
  { mastered :: Int
  , seen :: Int
  , slipping :: Int
  , total :: Int
  }

data Milestone
  = Everything Int
  | EveryWordSeen Int
  | Hundred Int
  | FirstMastered
  | Recovered

derive instance Eq Milestone

instance Show Milestone where
  show (Everything n) = "Everything " <> show n
  show (EveryWordSeen n) = "EveryWordSeen " <> show n
  show (Hundred n) = "Hundred " <> show n
  show FirstMastered = "FirstMastered"
  show Recovered = "Recovered"

-- | How loudly to say it. Three steps rather than two so that the rare things
-- | stay rare: `Burst` happens twice in the life of a deck and `Flourish` ten
-- | times, which is what makes either of them mean anything.
data Fanfare
  = Burst
  | Flourish
  | Remark

derive instance Eq Fanfare

instance Show Fanfare where
  show Burst = "Burst"
  show Flourish = "Flourish"
  show Remark = "Remark"

fanfare :: Milestone -> Fanfare
fanfare = case _ of
  Everything _ -> Burst
  EveryWordSeen _ -> Burst
  Hundred _ -> Flourish
  FirstMastered -> Remark
  Recovered -> Remark

-- | At most one, and the biggest thing that happened.
-- |
-- | The order matters where two could fire at once: finishing the deck is also
-- | a hundred, and meeting every word is usually several hundreds at a time.
-- | Saying both would make the larger one smaller.
-- |
-- | Every one of these is something the finished screen does not otherwise
-- | say. A clean sweep was here once and came out again: the tally above
-- | already reads "20 cards · 20 got it · 0 again", so a line underneath
-- | saying "20 out of 20" was the same sentence twice.
reached :: Standing -> Standing -> Maybe Milestone
reached before after
  | after.total > 0 && after.mastered >= after.total && before.mastered < after.total =
      Just $ Everything after.total
  | after.total > 0 && after.seen >= after.total && before.seen < after.total =
      Just $ EveryWordSeen after.total
  | after.mastered / 100 > before.mastered / 100 =
      Just $ Hundred $ (after.mastered / 100) * 100
  | before.mastered == 0 && after.mastered > 0 =
      Just FirstMastered
  -- The one repeatable thing on this list, and the only one about words
  -- getting better rather than about totals getting bigger.
  | before.slipping > 0 && after.slipping == 0 =
      Just Recovered
  | otherwise =
      Nothing

-- | Facts, pleased about themselves. Every one of these says what happened
-- | rather than how well you did it — "that makes 200 words mastered", not
-- | "you are doing great" — which is the line worth holding: the app can be
-- | glad without being the sort that tells you so.
describe :: Milestone -> String
describe = case _ of
  Everything n -> "Every one of the " <> show n <> " words is yours!"
  EveryWordSeen n -> "You have now met all " <> show n <> " words!"
  Hundred n -> "You’ve now mastered " <> show n <> " words!"
  FirstMastered -> "Your first word mastered!"
  Recovered -> "Nothing is slipping any more!"
