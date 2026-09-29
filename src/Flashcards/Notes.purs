-- | Notes about the app, written from inside it. See #49.
-- |
-- | Most of what has improved this app came from using it and noticing
-- | something, and a thing noticed on a train is gone by the time there is a
-- | keyboard. So a note is written where the complaint happened, and carries
-- | what was on screen, so that it does not have to be typed on a phone.
-- |
-- | One list for the whole app rather than one per page: a note is about the
-- | app, and it is read in one place. Each note says which page it came from.
-- |
-- | Kept on the device and got out by copying, deliberately. Syncing needs a
-- | merge that `Progress.merge` is not — notes are append-only, so two devices
-- | that each wrote one offline must both keep theirs — and that is its own
-- | piece of work. Filing issues straight from here would put a token behind a
-- | pairing key, which is a door key and not a password.
module Flashcards.Notes
  ( Note
  , currentVersion
  , export
  , fromJson
  , stamp
  , toJson
  , unreadable
  )
  where

import Prelude

import Data.Argonaut.Core (Json, jsonEmptyObject)
import Data.Argonaut.Decode (JsonDecodeError(..), decodeJson, (.:))
import Data.Argonaut.Encode ((:=), (~>))
import Data.DateTime (date, hour, minute, time)
import Data.DateTime as DateTime
import Data.DateTime.Instant (Instant, instant, toDateTime, unInstant)
import Data.Either (Either(..), note)
import Data.Enum (fromEnum)
import Data.Newtype (unwrap)
import Data.String as String
import Data.Time.Duration (Milliseconds(..))
import Data.Traversable (traverse)

type Note =
  { at :: Instant
  -- | What was on screen when it was written, spelled by the page that knew:
  -- | `verbs · porpara.means · …`. A string rather than a record, because
  -- | the only thing that ever reads it is a person.
  , context :: String
  , text :: String
  }

-- | What a stored list that is not even JSON fails with.
unreadable :: JsonDecodeError
unreadable = TypeMismatch "notes"

currentVersion :: Int
currentVersion = 1

toJson :: Array Note -> Json
toJson notes =
  "version" := currentVersion
    ~> "notes" := (notes <#> \n ->
         "at" := unwrap (unInstant n.at)
           ~> "context" := n.context
           ~> "text" := n.text
           ~> jsonEmptyObject)
    ~> jsonEmptyObject

-- | Refuses a version it does not know rather than guessing at one: a newer
-- | app wrote it, and reading it as this one would lose whatever it added.
fromJson :: Json -> Either JsonDecodeError (Array Note)
fromJson json = do
  o <- decodeJson json
  version <- o .: "version"
  unless (version == currentVersion) $
    Left $ UnexpectedValue json
  raw <- o .: "notes"
  traverse one raw
  where
    one j = do
      n <- decodeJson j
      ms <- n .: "at"
      at <- note (UnexpectedValue j) $ instant $ Milliseconds ms
      context <- n .: "context"
      text <- n .: "text"
      pure { at, context, text }

-- | Every note as one piece of text, oldest first, for pasting wherever it is
-- | going next. Oldest first because that is the order things happened in and
-- | the order an issue would tell them.
export :: Array Note -> String
export notes =
  String.joinWith "\n\n" $ notes <#> \n ->
    stamp n.at <> " · " <> n.context <> "\n" <> n.text

-- | `2026-09-28 14:03 UTC`. In UTC, because a note may be read on another
-- | device in another zone, and a time that does not say which is a guess.
stamp :: Instant -> String
stamp at =
  show (fromEnum $ DateTime.year d) <> "-" <> pad (fromEnum $ DateTime.month d) <> "-"
    <> pad (fromEnum $ DateTime.day d) <> " "
    <> pad (fromEnum $ hour t) <> ":" <> pad (fromEnum $ minute t) <> " UTC"
  where
    dt = toDateTime at
    d = date dt
    t = time dt
    pad n = if n < 10 then "0" <> show n else show n
