-- | Everything the app remembers between sessions. This is also, byte for
-- | byte, the backup file format: `Flashcards.Storage` writes it to
-- | localStorage and `Flashcards.Backup` writes the same bytes to disk, so
-- | there is one codec and one validation path rather than two that drift.
module Flashcards.Types.Progress
  ( CardProgress
  , Progress
  , Saved
  , currentVersion
  , empty
  , entries
  , fromJson
  , insert
  , lookup
  , mapWithRank
  , merge
  , seenCount
  , toJson
  )
  where

import Prelude

import Data.Argonaut.Core (Json)
import Data.Argonaut.Decode (decodeJson)
import Data.Argonaut.Decode.Error (JsonDecodeError(..))
import Data.Argonaut.Encode (encodeJson)
import Data.DateTime.Instant (Instant, instant, unInstant)
import Data.Either (Either(..), note)
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), fromMaybe)
import Data.Newtype (unwrap)
import Data.Time.Duration (Milliseconds(..))
import Data.Traversable (traverse)
import Data.Tuple.Nested (type (/\), (/\))
import Flashcards.Types.Card (Rank(..), rankToInt)
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Direction as Direction

-- | `box` is the Leitner box: 0 is "still learning, show me again this
-- | session", 5 is "retired for two months".
-- |
-- | `lapses` and `missed` count different things on purpose. A lapse is
-- | forgetting a word you had already learned, which is what marks a leech.
-- | `missed` is every wrong answer including the initial struggle, which is
-- | the only honest basis for an accuracy figure — `seen - missed` is right,
-- | whereas `seen - lapses` flatters you exactly where you are weakest.
type CardProgress =
  { box :: Int
  , due :: Instant
  , seen :: Int
  , lapses :: Int
  , missed :: Int
  , direction :: Direction
  }

newtype Progress = Progress (Map Rank CardProgress)

derive newtype instance Eq Progress
derive newtype instance Show Progress

-- | A decoded payload together with the deck it was written against. The
-- | caller decides what a mismatch means: `Storage` warns and carries on,
-- | because refusing to load your own history is worse than a little drift;
-- | `Backup` refuses, because combining two histories against different decks
-- | corrupts silently.
type Saved =
  { deck :: Maybe String
  , progress :: Progress
  }

-- | v1 had no deck fingerprint, v2 no miss count, v3 no direction. All stay
-- | readable and get written back at the current version on the next save.
-- | Absent fields read as their starting value — zero misses, recognition —
-- | which understates history that was never recorded rather than inventing
-- | any.
currentVersion :: Int
currentVersion = 4

empty :: Progress
empty = Progress Map.empty

lookup :: Rank -> Progress -> Maybe CardProgress
lookup rank (Progress m) = Map.lookup rank m

insert :: Rank -> CardProgress -> Progress -> Progress
insert rank cp (Progress m) = Progress $ Map.insert rank cp m

entries :: Progress -> Array (Rank /\ CardProgress)
entries (Progress m) = Map.toUnfoldable m

mapWithRank :: (Rank -> CardProgress -> CardProgress) -> Progress -> Progress
mapWithRank f (Progress m) = Progress $ Map.mapMaybeWithKey (\rank cp -> Just $ f rank cp) m

-- | How many of the 1000 words have been seen at least once.
seenCount :: Progress -> Int
seenCount (Progress m) = Map.size m

-- | Combine two histories card by card.
-- |
-- | `seen` only ever increases on a given device, so between two records for
-- | the same card the one with more sightings has strictly more history behind
-- | it and wins outright — no timestamps to reconcile, no lost sessions. Ties
-- | keep the left-hand record, which makes the result deterministic.
merge :: Progress -> Progress -> Progress
merge (Progress a) (Progress b) = Progress $ Map.unionWith furtherAlong a b
  where
    furtherAlong x y = if y.seen > x.seen then y else x

type Wire =
  { version :: Int
  , deck :: Maybe String
  , cards :: Array WireCard
  }

type WireCard =
  { rank :: Int
  , box :: Int
  , due :: Number
  , seen :: Int
  , lapses :: Int
  , missed :: Maybe Int
  , direction :: Maybe String
  }

toJson :: String -> Progress -> Json
toJson deck (Progress m) = encodeJson
  { version: currentVersion
  , deck: Just deck
  , cards: toWire <$> pairs
  }
  where
    pairs = Map.toUnfoldable m :: Array (Rank /\ CardProgress)

    toWire (rank /\ cp) =
      { rank: rankToInt rank
      , box: cp.box
      , due: unwrap $ unInstant cp.due
      , seen: cp.seen
      , lapses: cp.lapses
      , missed: Just cp.missed
      , direction: Just $ Direction.toString cp.direction
      }

fromJson :: Json -> Either JsonDecodeError Saved
fromJson json = do
  wire <- decodeJson json :: Either JsonDecodeError Wire
  -- Only reject the future. Older payloads are readable by construction.
  when (wire.version > currentVersion) $
    Left $ TypeMismatch $ "progress was written by a newer version of the app (" <> show wire.version <> ")"
  progress <- Progress <<< Map.fromFoldable <$> traverse fromWire wire.cards
  pure { deck: wire.deck, progress }
  where
    fromWire w = do
      due <- note (TypeMismatch "due is not a valid instant") $ instant $ Milliseconds w.due
      pure $ Rank w.rank /\
        { box: w.box
        , due
        , seen: w.seen
        , lapses: w.lapses
        , missed: fromMaybe 0 w.missed
        , direction: fromMaybe Recognition $ Direction.fromString =<< w.direction
        }
