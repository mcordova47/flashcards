module Flashcards.Types.Direction
  ( Direction(..)
  , fromString
  , toString
  )
  where

import Prelude

import Data.Maybe (Maybe(..))

-- | Which way a card is currently being asked.
-- |
-- | These are different skills, not two views of one. Recognising `encontrar`
-- | is far easier than producing it from "to find", so a card earns its way
-- | from one to the other rather than being tested both ways at once.
data Direction
  = Recognition
  | Production

derive instance Eq Direction
derive instance Ord Direction

instance Show Direction where
  show Recognition = "Recognition"
  show Production = "Production"

toString :: Direction -> String
toString = case _ of
  Recognition -> "recognition"
  Production -> "production"

-- | Anything unrecognised — including a payload that predates directions —
-- | reads as recognition, which is where every card starts.
fromString :: String -> Maybe Direction
fromString = case _ of
  "recognition" -> Just Recognition
  "production" -> Just Production
  _ -> Nothing
