module Test.Flashcards.VerbsSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Foldable (for_)
import Data.Maybe (Maybe(..))
import Flashcards.Exercise (Verdict(..))
import Flashcards.Pages.Verbs.Model (Phase(..), typing)
import Flashcards.Types.Progress as Progress
import Flashcards.Data.Verbs.Spanish (table)
import Flashcards.Verbs.Table (Person(..), Tense(..), formOf)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = do
  -- Asserted by hand rather than by tools/check-verbs.mjs, which can only say
  -- a cell is irregular, not that the irregular form is the right one.
  describe "the Spanish conjugation table" do
    it "has fui for both ser and ir" do
      formOf "ser" Preterite Sg1 table `shouldEqual` Just "fui"
      formOf "ir" Preterite Sg1 table `shouldEqual` Just "fui"

    it "has voy and doy" do
      formOf "ir" Present Sg1 table `shouldEqual` Just "voy"
      formOf "dar" Present Sg1 table `shouldEqual` Just "doy"

    -- The 2010 rules: a monosyllable takes no accent, except a diacritic one.
    it "accents monosyllables the way the RAE does" do
      formOf "ver" Preterite Sg3 table `shouldEqual` Just "vio"
      formOf "reír" Preterite Sg3 table `shouldEqual` Just "rio"
      formOf "dar" Subjunctive Sg3 table `shouldEqual` Just "dé"

    -- `hay` is vocabulary, and already a card; haber's own paradigm is only
    -- usable with a participle. See #12.
    it "leaves haber out" do
      formOf "haber" Present Sg3 table `shouldEqual` Nothing

    it "has all twenty cells for every verb" do
      let verbs = Array.nub (map _.infinitive table)
      Array.length table `shouldEqual` (Array.length verbs * 20)

  -- After the check the echo reads `typed`, so it must not move.
  describe "typing into the answer box" do
    let
      base =
        { progress: Progress.empty, queue: [], shown: Nothing, typed: "nada"
        , got: 0, again: 0, phase: Asked, modal: Nothing, at: Nothing
        , syncKey: Nothing, sent: Nothing, offline: false, loaded: true
        }

    it "is taken while the question is asked" do
      (typing "nadaX" base).typed `shouldEqual` "nadaX"

    it "is ignored once the answer has been compared" do
      for_ [ Exact, Wrong ] \verdict ->
        (typing "nadaXYZ" base { phase = Compared verdict }).typed `shouldEqual` "nada"

    it "is ignored once an answer is revealed or being graded" do
      for_ [ Revealed, Judging ] \phase ->
        (typing "nadaXYZ" base { phase = phase }).typed `shouldEqual` "nada"
