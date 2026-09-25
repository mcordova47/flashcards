module Test.Flashcards.PageSpec
  ( spec
  )
  where

import Prelude

import Data.Maybe (Maybe(..))
import Flashcards.Language as Language
import Flashcards.Page (Page(..))
import Flashcards.Page as Page
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

cards :: String -> Page
cards code = Cards $ case Language.byCode code of
  Just language -> language
  Nothing -> Language.default

spec :: Spec Unit
spec = do
  describe "the path names the page" do
    it "reads the flashcards, in a language" do
      Page.fromPath "/de" `shouldEqual` Just (cards "de")
      Page.fromPath "/es" `shouldEqual` Just (cards "es")

    it "and the verb drills" do
      Page.fromPath "/verbs" `shouldEqual` Just Verbs

    it "tolerating a trailing slash" do
      Page.fromPath "/de/" `shouldEqual` Just (cards "de")

    it "reads nothing out of the root, on purpose" do
      Page.fromPath "/" `shouldEqual` Nothing

    -- The reason this module exists. `/verbs` used to come back Nothing here,
    -- fall through to the saved language, and serve the flashcards — and the
    -- SPA catch-all returns 200 for every path, so nothing said otherwise.
    it "and nothing out of a path naming no page we have" do
      Page.fromPath "/fr" `shouldEqual` Nothing
      Page.fromPath "/nonsense" `shouldEqual` Nothing

    it "round-trips" do
      Page.fromPath (Page.pathFor Verbs) `shouldEqual` Just Verbs
      Page.fromPath (Page.pathFor (cards "de")) `shouldEqual` Just (cards "de")

  describe "whether a path is asking for anything" do
    it "the root is not" do
      Page.names "/" `shouldEqual` false
      Page.names "" `shouldEqual` false

    -- The difference between "open wherever I left off" and "open the page I
    -- asked for", which is what decides whether the address bar gets put right.
    it "but a path that named something we do not have is" do
      Page.names "/nonsense" `shouldEqual` true
      Page.names "/verbs" `shouldEqual` true

  describe "which page to open" do
    it "lets a shared link win over what the reader was studying" do
      Page.resolve "/de" (Just "es") `shouldEqual` cards "de"

    it "and a link to another page win over both" do
      Page.resolve "/verbs" (Just "es") `shouldEqual` Verbs

    it "falls back to their own language at the root" do
      Page.resolve "/" (Just "de") `shouldEqual` cards "de"

    it "and to the default when they have made no choice" do
      Page.resolve "/" Nothing `shouldEqual` cards Language.default.code

    it "ignores a saved language this build no longer ships" do
      Page.resolve "/" (Just "fr") `shouldEqual` cards Language.default.code

    it "ignores a path naming a page it does not have" do
      Page.resolve "/fr" (Just "de") `shouldEqual` cards "de"
