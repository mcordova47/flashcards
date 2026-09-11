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
  , Tally
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
  , total :: Int
  }

-- | What the session itself came to.
type Tally =
  { answered :: Int
  , again :: Int
  }

data Milestone
  = Everything Int
  | EveryWordSeen Int
  | Hundred Int
  | FirstMastered
  | NothingMissed Int

derive instance Eq Milestone

instance Show Milestone where
  show (Everything n) = "Everything " <> show n
  show (EveryWordSeen n) = "EveryWordSeen " <> show n
  show (Hundred n) = "Hundred " <> show n
  show FirstMastered = "FirstMastered"
  show (NothingMissed n) = "NothingMissed " <> show n

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
  NothingMissed _ -> Remark

-- | At most one, and the biggest thing that happened.
-- |
-- | The order matters where two could fire at once: finishing the deck is also
-- | a hundred, and a session that masters your first word is also very likely
-- | one with nothing missed. Saying both would make the larger one smaller.
-- |
-- | `smallest` keeps a three-card catch-up session from counting as a clean
-- | sweep. Early on almost every answer is right — new words fast-track on
-- | first sight — so without it the smallest tier would fire constantly and
-- | stop registering.
reached :: Int -> Standing -> Standing -> Tally -> Maybe Milestone
reached smallest before after tally
  | after.total > 0 && after.mastered >= after.total && before.mastered < after.total =
      Just $ Everything after.total
  | after.total > 0 && after.seen >= after.total && before.seen < after.total =
      Just $ EveryWordSeen after.total
  | after.mastered / 100 > before.mastered / 100 =
      Just $ Hundred $ (after.mastered / 100) * 100
  | before.mastered == 0 && after.mastered > 0 =
      Just FirstMastered
  | tally.answered >= smallest && tally.again == 0 =
      Just $ NothingMissed tally.answered
  | otherwise =
      Nothing

-- | Said as a fact rather than as praise. The app's register elsewhere is
-- | "Nothing due for another 4 hours"; being told "Amazing job!" by a
-- | flashcard would be a different app.
describe :: Milestone -> String
describe = case _ of
  Everything n -> "Every one of the " <> show n <> " words is yours."
  EveryWordSeen n -> "You have now met all " <> show n <> " words."
  Hundred n -> "That makes " <> show n <> " words mastered."
  FirstMastered -> "Your first word mastered."
  NothingMissed n -> show n <> " out of " <> show n <> "."
