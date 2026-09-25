module Test.Flashcards.VerbsSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
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
