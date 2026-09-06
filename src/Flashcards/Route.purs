-- | The path names the language, so a link can be shared: `/de` opens German
-- | for whoever you send it to, whatever they were last studying.
-- |
-- | Bare `/` deliberately does not: it falls back to the reader's own saved
-- | choice, so the installed app reopens where they left off rather than
-- | resetting to the default every time.
module Flashcards.Route
  ( current
  , replace
  )
  where

import Prelude

import Effect (Effect)
import Effect.Uncurried (EffectFn1, runEffectFn1)

foreign import current :: Effect String

-- | Keeps the address bar honest after a switch, without stacking a history
-- | entry every time you toggle.
replace :: String -> Effect Unit
replace = runEffectFn1 replace_

foreign import replace_ :: EffectFn1 String Unit
