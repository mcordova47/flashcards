module Test.Flashcards.ExerciseSpec
  ( spec
  )
  where

import Prelude

import Flashcards.Exercise (matches)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = do
  describe "whether a typed answer counts" do
    it "takes the answer" do
      matches "tenía" "tenía" `shouldEqual` true

    it "and refuses a different one" do
      matches "tenía" "tuve" `shouldEqual` false
      matches "tenía" "" `shouldEqual` false

    -- Nobody is practising the shift key.
    it "ignores case, surrounding space and a full stop" do
      matches "tenía" "  Tenía " `shouldEqual` true
      matches "tenía" "Tenía." `shouldEqual` true

    -- A missing accent is a real mistake but not the one being drilled, and
    -- being failed for one on a phone is how an app stops getting opened. The
    -- caller shows the accented form back.
    it "and accepts a missing accent" do
      matches "tenía" "tenia" `shouldEqual` true
      matches "comí" "comi" `shouldEqual` true
      matches "está" "esta" `shouldEqual` true

    -- Which is the opposite of how slugs treat them, where an accent is the
    -- whole difference between two words. Here it distinguishes nothing.
    it "without flattening anything else" do
      matches "tenía" "tenían" `shouldEqual` false
      matches "año" "ano" `shouldEqual` false
