module Test.Flashcards.AccentSpec
  ( spec
  )
  where

import Prelude

import Data.Maybe (Maybe(..))
import Flashcards.Accent as Accent
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = do
  describe "preferred accent" do
    it "picks Mexico when the device has it" do
      Accent.preferred [ "es-ES", "es-MX" ] `shouldEqual` Just "es-MX"

    it "does not care what order the device lists them in" do
      Accent.preferred [ "es-MX", "es-ES" ] `shouldEqual` Just "es-MX"

    it "falls back to Spain when there is no Mexican voice" do
      Accent.preferred [ "es-AR", "es-ES" ] `shouldEqual` Just "es-ES"

    it "takes whatever exists when it recognises neither" do
      Accent.preferred [ "es-CO", "es-PE" ] `shouldEqual` Just "es-CO"

    it "has nothing to offer on a device with no Spanish voice" do
      Accent.preferred [] `shouldEqual` Nothing

  describe "resolving a remembered choice" do
    it "honours a remembered accent the device still has" do
      Accent.resolve (Just "es-ES") [ "es-ES", "es-MX" ] `shouldEqual` Just "es-ES"

    it "ignores one the device can no longer speak" do
      Accent.resolve (Just "es-AR") [ "es-ES", "es-MX" ] `shouldEqual` Just "es-MX"

    it "falls back to the default when nothing is remembered" do
      Accent.resolve Nothing [ "es-ES", "es-MX" ] `shouldEqual` Just "es-MX"

    it "has nothing to resolve before the voice list arrives" do
      Accent.resolve (Just "es-MX") [] `shouldEqual` Nothing

  describe "accent labels" do
    it "names the locales a learner is likely to meet" do
      Accent.label "es-MX" `shouldEqual` "Mexico"
      Accent.label "es-ES" `shouldEqual` "Spain"
      Accent.label "es-419" `shouldEqual` "Latin America"

    it "shows an unrecognised tag rather than hiding the option" do
      Accent.label "es-GQ" `shouldEqual` "es-GQ"
