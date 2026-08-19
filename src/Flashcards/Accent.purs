-- | Which Spanish an utterance is spoken in. The set of choices is whatever
-- | the device actually has installed — never a hardcoded list — so this
-- | module only deals with naming and picking among what it is handed.
module Flashcards.Accent
  ( label
  , preferred
  , resolve
  )
  where

import Prelude

import Control.Alt ((<|>))
import Data.Array as Array
import Data.Maybe (Maybe(..))

-- | Latin American Spanish is what a learner in the US is overwhelmingly more
-- | likely to meet, and Castilian's *ceceo* is a real difference to train into
-- | your ear — so Mexico wins when the device offers it, Spain is the fallback,
-- | and failing both, whatever exists.
preferred :: Array String -> Maybe String
preferred available =
  Array.find (_ == "es-MX") available
    <|> Array.find (_ == "es-ES") available
    <|> Array.head available

-- | A remembered choice only counts if this device still has that voice —
-- | the preference is per-device, and devices disagree about what they can
-- | speak. Otherwise fall back to the preferred default.
resolve :: Maybe String -> Array String -> Maybe String
resolve saved available = case saved of
  Just chosen | Array.elem chosen available -> Just chosen
  _ -> preferred available

-- | Locales the deck is plausibly spoken in. Anything unrecognised shows its
-- | raw tag, which is ugly but honest and beats hiding a real option.
label :: String -> String
label = case _ of
  "es-419" -> "Latin America"
  "es-AR" -> "Argentina"
  "es-CL" -> "Chile"
  "es-CO" -> "Colombia"
  "es-ES" -> "Spain"
  "es-MX" -> "Mexico"
  "es-PE" -> "Peru"
  "es-US" -> "United States"
  other -> other
