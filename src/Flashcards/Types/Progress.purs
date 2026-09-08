-- | Everything the app remembers between sessions. This is also, byte for
-- | byte, the backup file format: `Flashcards.Storage` writes it to
-- | localStorage and `Flashcards.Backup` writes the same bytes to disk, so
-- | there is one codec and one validation path rather than two that drift.
-- |
-- | Keyed by slug, not by rank. A rank is a position and moves whenever the
-- | deck is edited; a slug is frozen when the card is first written down. See
-- | `Flashcards.Types.Card`.
module Flashcards.Types.Progress
  ( CardProgress
  , Progress
  , Saved
  , SavedCard
  , currentVersion
  , empty
  , entries
  , fromEntries
  , fromJson
  , insert
  , lookup
  , mapWithSlug
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
import Flashcards.Types.Card (Rank(..), Slug(..), slugToString)
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

newtype Progress = Progress (Map Slug CardProgress)

derive newtype instance Eq Progress
derive newtype instance Show Progress

-- | A decoded payload, still unresolved: entries written before v5 identify
-- | their card by rank, and turning a rank into a slug needs the deck. See
-- | `Flashcards.Deck.adopt`.
-- |
-- | No version field, deliberately. Which of the two identifiers an entry
-- | carries is the thing that matters, and reading that off the entry itself
-- | is both simpler and truer than trusting a number in the header.
type Saved =
  { language :: Maybe String
  , deck :: Maybe String
  , cards :: Array SavedCard
  }

-- | Exactly one of `slug` and `rank` is present in practice: v5 writes the
-- | first, everything before it wrote the second.
type SavedCard =
  { slug :: Maybe Slug
  , rank :: Maybe Rank
  , progress :: CardProgress
  }

-- | v1 had no deck fingerprint, v2 no miss count, v3 no direction, and v4 was
-- | keyed by rank. All stay readable, and absent fields read as their starting
-- | value rather than being invented.
currentVersion :: Int
currentVersion = 5

empty :: Progress
empty = Progress Map.empty

lookup :: Slug -> Progress -> Maybe CardProgress
lookup slug (Progress m) = Map.lookup slug m

insert :: Slug -> CardProgress -> Progress -> Progress
insert slug cp (Progress m) = Progress $ Map.insert slug cp m

entries :: Progress -> Array (Slug /\ CardProgress)
entries (Progress m) = Map.toUnfoldable m

fromEntries :: Array (Slug /\ CardProgress) -> Progress
fromEntries = Progress <<< Map.fromFoldable

mapWithSlug :: (Slug -> CardProgress -> CardProgress) -> Progress -> Progress
mapWithSlug f (Progress m) = Progress $ Map.mapMaybeWithKey (\slug cp -> Just $ f slug cp) m

-- | How many words have been seen at least once.
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

-- | What is read. Every field a past version could omit is optional, and
-- | `slug` against `rank` is the v5 boundary itself: exactly one of them is
-- | ever present.
type Wire =
  { version :: Int
  , language :: Maybe String
  , deck :: Maybe String
  , cards :: Array WireCard
  }

type WireCard =
  { slug :: Maybe String
  , rank :: Maybe Int
  , box :: Int
  , due :: Number
  , seen :: Int
  , lapses :: Int
  , missed :: Maybe Int
  , direction :: Maybe String
  }

-- | What is written, which is deliberately not `WireCard`. Argonaut renders an
-- | absent `Maybe` field as `"rank":null`, and a dozen dead bytes on each of a
-- | thousand cards is a real cost in a file people mail to themselves.
type WrittenCard =
  { slug :: String
  , box :: Int
  , due :: Number
  , seen :: Int
  , lapses :: Int
  , missed :: Int
  , direction :: String
  }

-- | The language is written from v5 on, because the fingerprint stopped being
-- | a gate the moment slugs made a moved deck harmless — and it was the only
-- | thing stopping a German file being poured into the Spanish deck. Nearly
-- | every German slug is inert there, which is the trouble: it would look like
-- | a thousand words learned, and `mal` is in both decks.
toJson :: String -> String -> Progress -> Json
toJson language deck progress = encodeJson
  { version: currentVersion
  , language
  , deck
  , cards: written <$> entries progress
  }
  where
    written :: Slug /\ CardProgress -> WrittenCard
    written (slug /\ cp) =
      { slug: slugToString slug
      , box: cp.box
      , due: unwrap $ unInstant cp.due
      , seen: cp.seen
      , lapses: cp.lapses
      , missed: cp.missed
      , direction: Direction.toString cp.direction
      }

fromJson :: Json -> Either JsonDecodeError Saved
fromJson json = do
  wire <- decodeJson json :: Either JsonDecodeError Wire
  -- Only reject the future. Older payloads are readable by construction.
  when (wire.version > currentVersion) $
    Left $ TypeMismatch $ "progress was written by a newer version of the app (" <> show wire.version <> ")"
  cards <- traverse fromWire wire.cards
  pure { language: wire.language, deck: wire.deck, cards }
  where
    fromWire w = do
      due <- note (TypeMismatch "due is not a valid instant") $ instant $ Milliseconds w.due
      pure
        { slug: Slug <$> w.slug
        , rank: Rank <$> w.rank
        , progress:
            { box: w.box
            , due
            , seen: w.seen
            , lapses: w.lapses
            , missed: fromMaybe 0 w.missed
            , direction: fromMaybe Recognition $ Direction.fromString =<< w.direction
            }
        }
