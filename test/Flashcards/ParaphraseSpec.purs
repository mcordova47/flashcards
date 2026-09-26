module Test.Flashcards.ParaphraseSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Data.Set as Set
import Flashcards.Data.Paraphrase.Spanish (prompts)
import Flashcards.Data.Sentences.Spanish (sentences)
import Flashcards.Data.Verbs.Spanish (table)
import Flashcards.Exercise (Answer(..))
import Flashcards.Types.Card (Slug(..), slugToString)
import Flashcards.Verbs.Paraphrase (Prompt, Trap(..), exercise, exercises, rubric)
import Flashcards.Verbs.Shift as Shift
import Flashcards.Verbs.Table (Person(..), Tense(..))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = do
  describe "the paraphrase rubric" do
    -- Only the trap was in doubt, so only the trap is phrased as a choice.
    -- Saying "imperfect, not preterite" where the tense was never in question
    -- teaches a confusion that was not there.
    it "phrases the verb as the choice when the verb is the trap" do
      rubric doorOpen `shouldEqual`
        [ "estar, not ser", "present", "third person singular" ]

    it "and the tense when the tense is" do
      rubric knewAnswer `shouldEqual`
        [ "saber", "imperfect, not preterite", "first person singular" ]

    it "names every person it can be given" do
      (rubric <<< asked <$> [ Sg1, Sg2, Sg3, Pl1, Pl3 ] # map Array.last) `shouldEqual`
        map Just
          [ "first person singular", "second person singular", "third person singular"
          , "first person plural", "third person plural"
          ]

  describe "a paraphrase exercise" do
    it "is self-graded, because many answers are right" do
      case (exercise doorOpen).answer of
        SelfGraded g -> g.model `shouldEqual` "La puerta está abierta."
        Checked _ -> "self-graded" `shouldEqual` "checked"

    it "asks nothing before the reveal beyond the prompt" do
      (exercise doorOpen).hint `shouldEqual` ""

  describe "the corpus" do
    let mine = exercises prompts

    it "gives every prompt its own item" do
      Set.size (Set.fromFoldable (map _.slug mine)) `shouldEqual` Array.length prompts

    it "keyed by the frozen id, not by anything that gets reworded" do
      Array.head (map _.slug mine) `shouldEqual` Just (Slug "paraphrase.door-open")

    -- Six of these verbs are also in the tense-shift bank, in tenses it
    -- reaches. One slug space would have a paraphrase credit a shift and the
    -- other way about, and they are not the same skill.
    it "shares no item with the tense shift" do
      let shifts = Set.fromFoldable $ map _.slug $ Shift.exercises table sentences
      Array.filter (\e -> Set.member e.slug shifts) mine # map (slugToString <<< _.slug)
        # shouldEqual []
  where
    doorOpen = base
    knewAnswer = base
      { verb = "saber", tense = Imperfect, person = Sg1, trap = OnTense, against = "preterite" }
    asked person = base { person = person }

base :: Prompt
base =
  { id: "door-open"
  , asked: "How would you tell me the door is open?"
  , model: "La puerta está abierta."
  , verb: "estar"
  , tense: Present
  , person: Sg3
  , trap: OnVerb
  , against: "ser"
  }
