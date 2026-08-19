-- | Pronunciation through the browser's own speech synthesis: no dependency,
-- | no API key, no audio files to ship. On Apple platforms the voices live on
-- | the device, so it keeps working offline like everything else here.
module Flashcards.Speech
  ( onAccents
  , speak
  , supported
  )
  where

import Prelude

import Effect (Effect)
import Effect.Uncurried (EffectFn1, EffectFn2, mkEffectFn1, runEffectFn1, runEffectFn2)

-- | Whether the engine exists at all. Checked once at startup so the control
-- | can be left out entirely rather than offered and doing nothing.
foreign import supported :: Effect Boolean

-- | The Spanish locales this device can actually speak, sorted. Read at
-- | runtime because the answer differs per machine — a Mac has es-ES and
-- | es-MX, an Android phone might have es-US, a bare Linux box neither.
-- |
-- | A callback rather than a plain read: engines populate their voice list
-- | asynchronously, and the list is reliably empty during startup. This fires
-- | once now if anything is known, and again when the engine catches up.
onAccents :: (Array String -> Effect Unit) -> Effect Unit
onAccents handler = runEffectFn1 onAccents_ $ mkEffectFn1 handler

foreign import onAccents_ :: EffectFn1 (EffectFn1 (Array String) Unit) Unit

speak :: String -> String -> Effect Unit
speak = runEffectFn2 speak_

foreign import speak_ :: EffectFn2 String String Unit
