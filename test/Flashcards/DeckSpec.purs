module Test.Flashcards.DeckSpec
  ( spec
  )
  where

import Prelude

import Data.Maybe (Maybe(..))
import Flashcards.Data.Deck.Spanish as Spanish
import Flashcards.Deck as Deck
import Flashcards.Types.Card (Card, Rank(..))
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

-- | Two English sides deliberately collide, as they do in the real deck.
deck :: Array Card
deck =
  [ { rank: Rank 1, english: "that", spanish: "que" }
  , { rank: Rank 2, english: "to find", spanish: "encontrar" }
  , { rank: Rank 3, english: "that", spanish: "ese" }
  , { rank: Rank 4, english: "that", spanish: "aquel" }
  ]

spec :: Spec Unit
spec = do
  describe "deck index" do
    it "finds a card by rank" do
      (_.spanish <$> Deck.card (Rank 2) (Deck.index deck)) `shouldEqual` Just "encontrar"

    it "has nothing for a rank outside the deck" do
      Deck.card (Rank 99) (Deck.index deck) `shouldEqual` Nothing

  describe "valid answers for a production prompt" do
    it "gathers every Spanish word that answers one English side" do
      Deck.answersFor "that" (Deck.index deck) `shouldEqual` [ "que", "ese", "aquel" ]

    it "keeps them in frequency order, commonest reading first" do
      Deck.answersFor "that" (Deck.index deck) `shouldEqual` [ "que", "ese", "aquel" ]

    it "returns a single answer as a one-element set" do
      Deck.answersFor "to find" (Deck.index deck) `shouldEqual` [ "encontrar" ]

    it "returns nothing for an English side not in the deck" do
      Deck.answersFor "petunia" (Deck.index deck) `shouldEqual` []

  describe "against the real deck" do
    it "still finds six answers for 'that', the worst collision" do
      Deck.answersFor "that" (Deck.index Spanish.deck)
        `shouldEqual` [ "que", "ese", "aquel", "cuanto", "ése", "aquello" ]

    it "gives an unambiguous word exactly one answer" do
      Deck.answersFor "to find" (Deck.index Spanish.deck) `shouldEqual` [ "encontrar" ]
