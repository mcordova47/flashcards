-- | Keys pressed anywhere on the page, for the screens that want a keyboard
-- | as well as a thumb.
-- |
-- | Here rather than on a page because both pages want it and neither owns
-- | it. The listener is on the window, so it fires while a text box has
-- | focus: a page that has one should map only keys that do not type a
-- | character, which in practice means `Enter` and the arrows, or else ignore
-- | every key while the box is showing, as the cards do under the pairing
-- | sheet. A space typed into a box is not stopped, so it reaches both.
-- |
-- | Except from a textarea, which gets no page keys at all: a text box is
-- | where an answer goes and `Enter` submits it, but a textarea is for writing,
-- | and `Enter` there is a new line.
module Flashcards.Keys
  ( onKeyDown
  )
  where

import Prelude

import Effect (Effect)
import Effect.Uncurried (EffectFn1, mkEffectFn1, runEffectFn1)

onKeyDown :: (String -> Effect Unit) -> Effect Unit
onKeyDown handler = runEffectFn1 onKeyDown_ $ mkEffectFn1 handler

foreign import onKeyDown_ :: EffectFn1 (EffectFn1 String Unit) Unit
