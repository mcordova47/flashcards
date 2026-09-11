-- | Three seconds of rectangles, for the two moments in a deck's life that
-- | earn them.
-- |
-- | Skipped entirely under `prefers-reduced-motion`. The milestone says the
-- | same thing in words beside it, so nothing is lost by not drawing it.
module Flashcards.Confetti
  ( burst
  , stop
  )
  where

import Prelude

import Effect (Effect)

foreign import burst :: Effect Unit

foreign import stop :: Effect Unit
