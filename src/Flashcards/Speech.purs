-- | Pronunciation through the browser's own speech synthesis: no dependency,
-- | no API key, no audio files to ship. On Apple platforms the voices live on
-- | the device, so it keeps working offline like everything else here.
module Flashcards.Speech
  ( speak
  , supported
  )
  where

import Prelude

import Effect (Effect)
import Effect.Uncurried (EffectFn1, runEffectFn1)

-- | Whether the engine exists at all. Checked once at startup so the control
-- | can be left out entirely rather than offered and doing nothing.
foreign import supported :: Effect Boolean

speak :: String -> Effect Unit
speak = runEffectFn1 speak_

foreign import speak_ :: EffectFn1 String Unit
