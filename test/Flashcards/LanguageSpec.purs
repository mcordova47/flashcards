module Test.Flashcards.LanguageSpec
  ( spec
  )
  where

import Prelude

import Data.Maybe (Maybe(..))
import Flashcards.Language as Language
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = do
  describe "the path names the language" do
    it "reads a language out of a path" do
      (_.code <$> Language.fromPath "/de") `shouldEqual` Just "de"
      (_.code <$> Language.fromPath "/es") `shouldEqual` Just "es"

    it "tolerates a trailing slash" do
      (_.code <$> Language.fromPath "/de/") `shouldEqual` Just "de"

    it "reads nothing out of the root, on purpose" do
      (_.code <$> Language.fromPath "/") `shouldEqual` Nothing

    it "reads nothing out of a path naming no language we ship" do
      (_.code <$> Language.fromPath "/fr") `shouldEqual` Nothing

    it "round-trips" do
      (_.code <$> Language.fromPath (Language.pathFor Language.german)) `shouldEqual` Just "de"

  describe "which language to open" do
    it "lets a shared link win over what the reader was studying" do
      (Language.resolve "/de" (Just "es")).code `shouldEqual` "de"

    it "falls back to their own choice at the root" do
      (Language.resolve "/" (Just "de")).code `shouldEqual` "de"

    it "and to the default when they have made none" do
      (Language.resolve "/" Nothing).code `shouldEqual` Language.default.code

    it "ignores a saved language this build no longer ships" do
      (Language.resolve "/" (Just "fr")).code `shouldEqual` Language.default.code

    it "ignores a path naming one it does not ship" do
      (Language.resolve "/fr" (Just "de")).code `shouldEqual` "de"
