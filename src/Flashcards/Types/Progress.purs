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
  , fromJson
  , insert
  , lookup
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
import Data.Maybe (Maybe(..))
import Data.Newtype (unwrap)
import Data.Time.Duration (Milliseconds(..))
import Data.Traversable (traverse)
import Data.Tuple.Nested (type (/\), (/\))
import Flashcards.Types.Card (Rank(..), rankToInt)

-- | `box` is the Leitner box: 0 is "still learning, show me again this
-- | session", 5 is "retired for two months".
type CardProgress =
  { box :: Int
  , due :: Instant
  , seen :: Int
  , lapses :: Int
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

-- | v1 had no deck fingerprint. It is still readable — it predates any
-- | renumbering — and gets written back as v2 on the next save.
currentVersion :: Int
currentVersion = 2

empty :: Progress
empty = Progress Map.empty

lookup :: Rank -> Progress -> Maybe CardProgress
lookup rank (Progress m) = Map.lookup rank m

insert :: Rank -> CardProgress -> Progress -> Progress
insert rank cp (Progress m) = Progress $ Map.insert rank cp m

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
      pure $ Rank w.rank /\ { box: w.box, due, seen: w.seen, lapses: w.lapses }
