module Test.Flashcards.AccentSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Flashcards.Accent (Voice)
import Flashcards.Accent as Accent
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

-- Mirrors what a Mac reports: the real voice buried among novelty ones that
-- all carry a "(Spanish (Region))" suffix.
mac :: Array Voice
mac =
  [ { name: "Eddy (Spanish (Spain))", locale: "es-ES" }
  , { name: "Eddy (Spanish (Mexico))", locale: "es-MX" }
  , { name: "Mónica", locale: "es-ES" }
  , { name: "Paulina", locale: "es-MX" }
  , { name: "Rocko (Spanish (Mexico))", locale: "es-MX" }
  ]

-- What Spanish asks for, as `Flashcards.Language` supplies it.
wanted :: Array String
wanted = [ "es-MX", "es-ES" ]

spec :: Spec Unit
spec = do
  describe "reading the device's voice list" do
    it "collapses many voices into the locales they cover" do
      Accent.locales mac `shouldEqual` [ "es-ES", "es-MX" ]

    it "lists a locale's voices in the order the engine gave them" do
      Accent.voicesIn "es-MX" mac
        `shouldEqual` [ "Eddy (Spanish (Mexico))", "Paulina", "Rocko (Spanish (Mexico))" ]

  describe "picking a voice" do
    it "prefers the plainly-named voice over the novelty ones" do
      Accent.autoVoice "es-MX" mac `shouldEqual` Just "Paulina"

    it "settles for a novelty voice when that is all there is" do
      Accent.autoVoice "es-ES" [ { name: "Flo (Spanish (Spain))", locale: "es-ES" } ]
        `shouldEqual` Just "Flo (Spanish (Spain))"

    it "has nothing to offer for a locale the device cannot speak" do
      Accent.autoVoice "es-AR" mac `shouldEqual` Nothing

    it "keeps a remembered voice the device still has" do
      Accent.resolveVoice "es-MX" (Just "Rocko (Spanish (Mexico))") mac
        `shouldEqual` Just "Rocko (Spanish (Mexico))"

    it "ignores a remembered voice belonging to another locale" do
      Accent.resolveVoice "es-MX" (Just "Mónica") mac `shouldEqual` Just "Paulina"

  describe "cycling past a voice that does not work" do
    it "moves to the next voice in the locale" do
      Accent.nextIn "es-MX" (Just "Paulina") mac `shouldEqual` Just "Rocko (Spanish (Mexico))"

    it "wraps around at the end" do
      Accent.nextIn "es-MX" (Just "Rocko (Spanish (Mexico))") mac
        `shouldEqual` Just "Eddy (Spanish (Mexico))"

    it "starts at the beginning when nothing is selected" do
      Accent.nextIn "es-MX" Nothing mac `shouldEqual` Just "Eddy (Spanish (Mexico))"

    it "reaches every voice before repeating, so a working one is always findable" do
      let
        step acc _ = acc <> [ Accent.nextIn "es-MX" (join (Array.last acc)) mac ]
        visited = Array.foldl step [ Just "Paulina" ] [ 1, 2 ]
      Array.nub visited `shouldEqual` visited
      Array.length visited `shouldEqual` Array.length (Accent.voicesIn "es-MX" mac)
      Accent.nextIn "es-MX" (join (Array.last visited)) mac `shouldEqual` Just "Paulina"

    it "has nowhere to go for a locale the device cannot speak" do
      Accent.nextIn "es-AR" Nothing mac `shouldEqual` Nothing

  describe "preferred accent" do
    it "picks Mexico when the device has it" do
      Accent.preferred wanted [ "es-ES", "es-MX" ] `shouldEqual` Just "es-MX"

    it "does not care what order the device lists them in" do
      Accent.preferred wanted [ "es-MX", "es-ES" ] `shouldEqual` Just "es-MX"

    it "falls back to Spain when there is no Mexican voice" do
      Accent.preferred wanted [ "es-AR", "es-ES" ] `shouldEqual` Just "es-ES"

    it "takes whatever exists when it recognises neither" do
      Accent.preferred wanted [ "es-CO", "es-PE" ] `shouldEqual` Just "es-CO"

    it "has nothing to offer on a device with no Spanish voice" do
      Accent.preferred wanted [] `shouldEqual` Nothing

  describe "resolving a remembered choice" do
    it "honours a remembered accent the device still has" do
      Accent.resolve wanted (Just "es-ES") [ "es-ES", "es-MX" ] `shouldEqual` Just "es-ES"

    it "ignores one the device can no longer speak" do
      Accent.resolve wanted (Just "es-AR") [ "es-ES", "es-MX" ] `shouldEqual` Just "es-MX"

    it "falls back to the default when nothing is remembered" do
      Accent.resolve wanted Nothing [ "es-ES", "es-MX" ] `shouldEqual` Just "es-MX"

    it "has nothing to resolve before the voice list arrives" do
      Accent.resolve wanted (Just "es-MX") [] `shouldEqual` Nothing

  describe "accent labels" do
    it "names the locales a learner is likely to meet" do
      Accent.label "es-MX" `shouldEqual` "Mexico"
      Accent.label "es-ES" `shouldEqual` "Spain"
      Accent.label "es-419" `shouldEqual` "Latin America"

    it "shows an unrecognised tag rather than hiding the option" do
      Accent.label "es-GQ" `shouldEqual` "es-GQ"
