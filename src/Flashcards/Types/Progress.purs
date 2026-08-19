-- | Everything the app remembers between sessions. Persisted to localStorage;
-- | see `Flashcards.Storage`.
module Flashcards.Types.Progress
  ( CardProgress
  , Progress
  , currentVersion
  , empty
  , fromJson
  , insert
  , lookup
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
import Data.Maybe (Maybe)
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

-- | Bump when the on-disk shape changes; `fromJson` rejects anything else, and
-- | `Storage` falls back to a fresh start rather than guessing.
currentVersion :: Int
currentVersion = 1

empty :: Progress
empty = Progress Map.empty

lookup :: Rank -> Progress -> Maybe CardProgress
lookup rank (Progress m) = Map.lookup rank m

insert :: Rank -> CardProgress -> Progress -> Progress
insert rank cp (Progress m) = Progress $ Map.insert rank cp m

-- | How many of the 1000 words have been seen at least once.
seenCount :: Progress -> Int
seenCount (Progress m) = Map.size m

type Wire =
  { version :: Int
  , cards :: Array WireCard
  }

type WireCard =
  { rank :: Int
  , box :: Int
  , due :: Number
  , seen :: Int
  , lapses :: Int
  }

toJson :: Progress -> Json
toJson (Progress m) = encodeJson { version: currentVersion, cards: toWire <$> pairs }
  where
    pairs = Map.toUnfoldable m :: Array (Rank /\ CardProgress)

    toWire (rank /\ cp) =
      { rank: rankToInt rank
      , box: cp.box
      , due: unwrap $ unInstant cp.due
      , seen: cp.seen
      , lapses: cp.lapses
      }

fromJson :: Json -> Either JsonDecodeError Progress
fromJson json = do
  wire <- decodeJson json :: Either JsonDecodeError Wire
  if wire.version /= currentVersion then
    Left $ TypeMismatch $ "unsupported progress version " <> show wire.version
  else
    Progress <<< Map.fromFoldable <$> traverse fromWire wire.cards
  where
    fromWire w = do
      due <- note (TypeMismatch "due is not a valid instant") $ instant $ Milliseconds w.due
      pure $ Rank w.rank /\ { box: w.box, due, seen: w.seen, lapses: w.lapses }
