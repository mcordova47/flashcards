-- | Pronunciation through the browser's own speech synthesis: no dependency,
-- | no API key, no audio files to ship. On Apple platforms the voices live on
-- | the device, so it keeps working offline like everything else here.
module Flashcards.Speech
  ( onVoices
  , speak
  , supported
  )
  where

import Prelude

import Effect (Effect)
import Effect.Uncurried (EffectFn1, EffectFn3, mkEffectFn1, runEffectFn1, runEffectFn3)
import Flashcards.Accent (Voice)

-- | Whether the engine exists at all. Checked once at startup so the control
-- | can be left out entirely rather than offered and doing nothing.
foreign import supported :: Effect Boolean

-- | Every Spanish voice this device reports, in engine order.
-- |
-- | A callback rather than a plain read: engines populate their voice list
-- | asynchronously and it is reliably empty during startup. Fires once now if
-- | anything is known, and again when the engine catches up.
onVoices :: (Array Voice -> Effect Unit) -> Effect Unit
onVoices handler = runEffectFn1 onVoices_ $ mkEffectFn1 handler

-- | Speak `text` with the named voice. Falls back within the locale, then to
-- | any Spanish voice — never to no voice at all, which would hand the engine
-- | its own default: on a US machine, English reading Spanish.
speak :: String -> String -> String -> Effect Unit
speak = runEffectFn3 speak_

foreign import onVoices_ :: EffectFn1 (EffectFn1 (Array Voice) Unit) Unit

foreign import speak_ :: EffectFn3 String String String Unit
