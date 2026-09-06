-- | Everything that differs between one language and the next, in one place.
-- |
-- | Both decks are compiled into the bundle rather than fetched. Together they
-- | are a few tens of kilobytes, and switching language has to work with no
-- | signal like everything else here.
module Flashcards.Language
  ( Language
  , all
  , byCode
  , default
  , german
  , resolve
  , spanish
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..), fromMaybe)
import Flashcards.Data.Deck.German as German
import Flashcards.Data.Deck.Spanish as Spanish
import Flashcards.Types.Card (Card)

type Language =
  { code :: String
  , name :: String
  , deck :: Array Card
  , fingerprint :: String
  -- | Accents to prefer when the device offers a choice, best first.
  , accents :: Array String
  -- | What a rank means in this deck. The two sources order their words on
  -- | entirely different principles, and the progress screen says so.
  , ordering :: String
  -- | Shown when a session ends, in the language being learned.
  , done :: String
  -- | Spoken when trying out an accent or a voice. Chosen to make the
  -- | difference between accents audible, not just to demonstrate the voice.
  , preview :: String
  }

spanish :: Language
spanish =
  { code: "es"
  , name: "Spanish"
  , deck: Spanish.deck
  , fingerprint: Spanish.fingerprint
  -- Latin American Spanish is what a learner in the US is far more likely to
  -- meet, and Castilian's *ceceo* is a real difference to train into the ear.
  , accents: [ "es-MX", "es-ES" ]
  , ordering: "frequency"
  , done: "¡Bien hecho!"
  -- "grah-thee-as" in Spain against "grah-see-as" in Mexico.
  , preview: "gracias"
  }

german :: Language
german =
  { code: "de"
  , name: "German"
  , deck: German.deck
  , fingerprint: German.fingerprint
  , accents: [ "de-DE", "de-AT", "de-CH" ]
  -- A course vocabulary list, A1 then A2, alphabetical within each unit. Rank
  -- is a position in that curriculum, not a claim about how common a word is.
  , ordering: "course order"
  , done: "Gut gemacht!"
  -- Final -ig is the clearest regional tell: /ɪç/ in the north against /ɪk/
  -- further south.
  , preview: "richtig"
  }

all :: Array Language
all = [ spanish, german ]

default :: Language
default = spanish

byCode :: String -> Maybe Language
byCode code = Array.find (\l -> l.code == code) all

-- | A remembered choice, falling back to the default if it names a language
-- | this build no longer ships.
resolve :: Maybe String -> Language
resolve saved = fromMaybe default $ byCode =<< saved
