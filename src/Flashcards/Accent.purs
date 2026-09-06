-- | Which Spanish an utterance is spoken in, and by whom. The choices are
-- | always whatever the device actually reports — never a hardcoded list — so
-- | this module only names and picks among what it is handed.
module Flashcards.Accent
  ( Voice
  , autoVoice
  , forLanguage
  , label
  , locales
  , nextIn
  , preferred
  , resolve
  , resolveVoice
  , voicesIn
  )
  where

import Prelude

import Control.Alt ((<|>))
import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..))
import Data.String as String

type Voice =
  { name :: String
  , locale :: String
  }

-- | The voices belonging to one language, by BCP-47 prefix: "es", "de".
forLanguage :: String -> Array Voice -> Array Voice
forLanguage prefix = Array.filter \v -> String.take (String.length prefix) v.locale == prefix

locales :: Array Voice -> Array String
locales = Array.sort <<< Array.nub <<< map _.locale

-- | Names for one locale, kept in the order the engine reported them.
voicesIn :: String -> Array Voice -> Array String
voicesIn locale = map _.name <<< Array.filter (\v -> v.locale == locale)

-- | The first of the language's preferred accents that this device can
-- | actually speak, or failing all of them, whatever it has.
preferred :: Array String -> Array String -> Maybe String
preferred wanted available =
  Array.findMap (\w -> Array.find (_ == w) available) wanted <|> Array.head available

-- | A remembered choice only counts if this device still has it — the
-- | preference is per-device, and devices disagree about what they can speak.
resolve :: Array String -> Maybe String -> Array String -> Maybe String
resolve wanted saved available = case saved of
  Just chosen | Array.elem chosen available -> Just chosen
  _ -> preferred wanted available

-- | The automatic pick within a locale: prefer a plain name over the novelty
-- | voices, which on Apple platforms all carry a "(Spanish (Region))" suffix.
-- |
-- | This is only ever a guess. A voice can be listed with no asset behind it —
-- | macOS advertises Mónica and Paulina whether or not they are downloaded,
-- | and substitutes an English voice when they are not — and nothing in the
-- | API reveals that. Hence `nextIn`: the ear is the only reliable detector.
autoVoice :: String -> Array Voice -> Maybe String
autoVoice locale voices =
  Array.find (not <<< String.contains (Pattern "(")) names <|> Array.head names
  where
    names = voicesIn locale voices

resolveVoice :: String -> Maybe String -> Array Voice -> Maybe String
resolveVoice locale saved voices = case saved of
  Just chosen | Array.elem chosen (voicesIn locale voices) -> Just chosen
  _ -> autoVoice locale voices

-- | The next voice for this locale, wrapping at the end.
nextIn :: String -> Maybe String -> Array Voice -> Maybe String
nextIn locale current voices =
  -- `elemIndex` can only succeed on a non-empty array, so the wrap is safe.
  case current >>= flip Array.elemIndex names of
    Just i -> Array.index names $ (i + 1) `mod` Array.length names
    Nothing -> Array.head names
  where
    names = voicesIn locale voices

-- | Locales the deck is plausibly spoken in. Anything unrecognised shows its
-- | raw tag, which is ugly but honest and beats hiding a real option.
label :: String -> String
label = case _ of
  "de-AT" -> "Austria"
  "de-CH" -> "Switzerland"
  "de-DE" -> "Germany"
  "es-419" -> "Latin America"
  "es-AR" -> "Argentina"
  "es-CL" -> "Chile"
  "es-CO" -> "Colombia"
  "es-ES" -> "Spain"
  "es-MX" -> "Mexico"
  "es-PE" -> "Peru"
  "es-US" -> "United States"
  other -> other
