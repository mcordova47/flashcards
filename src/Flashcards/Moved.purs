-- | What a session did to the ladder: how many items went up a box, how many
-- | were met for the first time, and how many fell back.
-- |
-- | Pure, and a subtraction between two standings, like `Milestone`: the box
-- | each item had when it was first answered this session, and the box it has
-- | now. Nothing is stored beyond the first, which the page holds for as long
-- | as the session lasts, so there is no "already counted" to keep and nothing
-- | to arbitrate between two devices.
-- |
-- | A count of items, not a share of anything. See #29 for why the drills say
-- | none.
module Flashcards.Moved
  ( Before
  , Moved
  , describe
  , moved
  , remember
  )
  where

import Prelude

import Data.Array as Array
import Data.Map (Map)
import Data.Map as Map
import Data.Maybe (Maybe(..), maybe)
import Data.String as String
import Data.Tuple.Nested ((/\))
import Flashcards.Stats (plural)
import Flashcards.Types.Card (Slug)
import Flashcards.Types.Progress (Progress)
import Flashcards.Types.Progress as Progress

-- | The box each item had the first time this session answered it, `Nothing`
-- | for one never answered before.
type Before = Map Slug (Maybe Int)

type Moved = { climbed :: Int, met :: Int, fell :: Int }

-- | Note an item's standing as it is about to be answered. Only the first
-- | time counts: what an item was *before the session* is the thing to
-- | compare, and a second answer moves it from somewhere the session made.
remember :: Slug -> Progress -> Before -> Before
remember slug progress before
  | Map.member slug before = before
  | otherwise = Map.insert slug (_.box <$> Progress.lookup slug progress) before

-- | An item new to the session is *met*, not *climbed*: its first right answer
-- | lands it in box 3, and counting that as three steps up would make the
-- | first session the biggest there ever is. One missed and then got is the
-- | other way about: it fell back, and the line says so, because it did.
moved :: Before -> Progress -> Moved
moved before progress =
  Array.foldl count { climbed: 0, met: 0, fell: 0 } (Map.toUnfoldable before :: Array _)
  where
    count acc (slug /\ was) =
      let now = maybe 0 _.box $ Progress.lookup slug progress
      in case was of
        Nothing -> acc { met = acc.met + 1 }
        Just box
          | now > box -> acc { climbed = acc.climbed + 1 }
          | now < box -> acc { fell = acc.fell + 1 }
          | otherwise -> acc

-- | What to say, or nothing where there is nothing to say: a session that
-- | moved no box has no line, rather than a line of zeroes.
describe :: Moved -> Maybe String
describe m = case Array.catMaybes parts of
  [] -> Nothing
  said -> Just $ String.joinWith " · " said
  where
    parts =
      [ say m.climbed (\n -> show n <> " climbed a box")
      , say m.met (\n -> plural n "new item" <> " met")
      , say m.fell (\n -> show n <> " fell back")
      ]
    say n f = if n > 0 then Just (f n) else Nothing
