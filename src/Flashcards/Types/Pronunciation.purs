-- | How the words of a deck are said, by dialect. See #175.
-- |
-- | A dialect is named by the BCP 47 tag of the column it came from, so a
-- | second one is another entry in the array and nothing that reads this
-- | changes. Nothing in the app shows a transcription yet; the first reader is
-- | the game that studies against this deck (#169).
module Flashcards.Types.Pronunciation
  ( Dialect
  , Entry
  , ipa
  , tags
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe)
import Flashcards.Types.Card (Slug)

-- | `ipa` is the transcription alone: no slashes or brackets round it, and
-- | stress marked with `ˈ`. Whoever shows it adds the delimiters.
type Entry = { slug :: Slug, ipa :: String }

type Dialect = { tag :: String, entries :: Array Entry }

-- | The dialects a deck has, in the order its CSV lists them.
tags :: Array Dialect -> Array String
tags = map _.tag

-- | A word's transcription in one dialect. Nothing for a dialect the deck has
-- | no column for, and for a slug that is not in it.
ipa :: String -> Slug -> Array Dialect -> Maybe String
ipa tag slug dialects = do
  dialect <- Array.find (\d -> d.tag == tag) dialects
  entry <- Array.find (\e -> e.slug == slug) dialect.entries
  pure entry.ipa
