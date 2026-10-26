module Test.Flashcards.PronunciationSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Flashcards.Language as Language
import Flashcards.Types.Card (Slug(..))
import Flashcards.Types.Card as Card
import Flashcards.Types.Pronunciation as Pronunciation
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

say :: String -> String -> Maybe String
say tag slug = Pronunciation.ipa tag (Slug slug) Language.spanish.pronunciations

spec :: Spec Unit
spec = do
  describe "pronunciations" do
    it "reads a word back by its dialect tag" do
      say "es-MX" "yo" `shouldEqual` Just "ʝo"
      say "es-MX" "querer" `shouldEqual` Just "keˈɾeɾ"

    it "tells hiatus from a diphthong without a syllable dot" do
      say "es-MX" "día" `shouldEqual` Just "ˈdia"
      say "es-MX" "bien" `shouldEqual` Just "bjen"

    it "keeps a slashed row, a phrase and a (se) row as the word side has them" do
      say "es-MX" "el / la" `shouldEqual` Just "el / la"
      say "es-MX" "por favor" `shouldEqual` Just "poɾ faˈboɾ"
      say "es-MX" "ir(se)" `shouldEqual` Just "iɾ(se)"

    it "has nothing for a dialect the deck has no column for" do
      say "es-ES" "yo" `shouldEqual` Nothing

    it "has nothing for a slug outside the deck" do
      say "es-MX" "petunia" `shouldEqual` Nothing

    it "gives every Spanish card an es-MX transcription, keyed by its slug" do
      let slugs = Language.spanish.deck <#> _.slug
      Array.all (\s -> Pronunciation.ipa "es-MX" s Language.spanish.pronunciations /= Nothing) slugs
        `shouldEqual` true
      map Card.slugToString slugs `shouldEqual` map (Card.slugToString <<< _.slug)
        (Array.concatMap _.entries Language.spanish.pronunciations)

    it "names its dialects, and German has none yet" do
      Pronunciation.tags Language.spanish.pronunciations `shouldEqual` [ "es-MX" ]
      Pronunciation.tags Language.german.pronunciations `shouldEqual` []
