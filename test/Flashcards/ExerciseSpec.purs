module Test.Flashcards.ExerciseSpec
  ( spec
  )
  where

import Prelude

import Data.Array.NonEmpty as NonEmpty
import Data.Maybe (Maybe(..))
import Flashcards.Exercise (Answer(..), Exercise, Verdict(..), matches, pick, pools)
import Flashcards.Types.Card (Slug(..))
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Progress (CardProgress)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (fail, shouldEqual)

spec :: Spec Unit
spec = do
  describe "whether a typed answer counts" do
    it "takes the answer" do
      matches "tenía" "tenía" `shouldEqual` Exact

    it "and refuses a different one" do
      matches "tenía" "tuve" `shouldEqual` Wrong
      matches "tenía" "" `shouldEqual` Wrong

    -- Nobody is practising the shift key.
    it "ignores case, surrounding space and terminal punctuation" do
      matches "tenía" "  Tenía " `shouldEqual` Exact
      matches "tenía" "Tenía." `shouldEqual` Exact
      matches "tenía" "tenía!" `shouldEqual` Exact
      matches "tenía" "tenía?" `shouldEqual` Exact

    -- A missing accent is a real mistake but not the one being drilled, and
    -- being failed for one on a phone is how an app stops getting opened. It
    -- counts, and says which it was, so the caller can show the accent back.
    it "and accepts a missing accent, saying so" do
      matches "tenía" "tenia" `shouldEqual` Unaccented
      matches "comí" "comi" `shouldEqual` Unaccented
      matches "está" "esta" `shouldEqual` Unaccented
      matches "tenía" " Tenia. " `shouldEqual` Unaccented

    -- The same forgiveness in the other direction: a stray accent is as
    -- little the point as a missing one.
    it "or an accent where there is none" do
      matches "fui" "fuí" `shouldEqual` Unaccented

    -- Which is the opposite of how slugs treat them, where an accent is the
    -- whole difference between two words. Here it distinguishes nothing.
    it "without flattening anything else" do
      matches "tenía" "tenían" `shouldEqual` Wrong
      matches "año" "ano" `shouldEqual` Wrong

  describe "an item with more than one way to ask it" do
    let
      ask slug prompt =
        { slug: Slug slug, prompt, hint: "", frame: { before: "", after: "" }, answer: Checked "" } :: Exercise
      bank =
        [ ask "tener.preterite" "tengo mucho trabajo"
        , ask "tener.imperfect" "tengo mucho trabajo"
        , ask "tener.preterite" "mis padres tienen una casa grande"
        ]
      promptsOf = map (map _.prompt <<< NonEmpty.toArray <<< _.exercises)

    it "is one pool per slug, in the order the slugs first appear" do
      map _.slug (pools bank) `shouldEqual` [ Slug "tener.preterite", Slug "tener.imperfect" ]
      promptsOf (pools bank) `shouldEqual`
        [ [ "tengo mucho trabajo", "mis padres tienen una casa grande" ]
        , [ "tengo mucho trabajo" ]
        ]

    it "asks a different one on a later sighting" do
      case pools bank of
        [ preterite, _ ] -> do
          (pick Nothing preterite).prompt `shouldEqual` "tengo mucho trabajo"
          (pick (Just $ seenTimes 1) preterite).prompt `shouldEqual` "mis padres tienen una casa grande"
          (pick (Just $ seenTimes 2) preterite).prompt `shouldEqual` "tengo mucho trabajo"
        _ ->
          fail "expected two pools"

    it "and the only one there is, when there is one" do
      case pools bank of
        [ _, imperfect ] ->
          (pick (Just $ seenTimes 7) imperfect).prompt `shouldEqual` "tengo mucho trabajo"
        _ ->
          fail "expected two pools"
  where
    seenTimes :: Int -> CardProgress
    seenTimes n = { box: 1, due: bottom, seen: n, lapses: 0, missed: 0, direction: Recognition }
