module Test.Flashcards.DeckSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..))
import Flashcards.Data.Deck.Spanish as Spanish
import Flashcards.Deck as Deck
import Data.DateTime.Instant (Instant, instant)
import Data.Time.Duration (Milliseconds(..))
import Flashcards.Scheduler as Scheduler
import Flashcards.Types.Card (Card, Rank(..))
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Progress as Progress
import Partial.Unsafe (unsafePartial)
import Data.Maybe (fromJust)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

-- | Two English sides deliberately collide, as they do in the real deck.
deck :: Array Card
deck =
  [ { rank: Rank 1, english: "that", word: "que", example: "" }
  , { rank: Rank 2, english: "to find", word: "encontrar", example: "" }
  , { rank: Rank 3, english: "that", word: "ese", example: "" }
  , { rank: Rank 4, english: "that", word: "aquel", example: "" }
  ]

epoch :: Instant
epoch = unsafePartial $ fromJust $ instant $ Milliseconds 0.0

spec :: Spec Unit
spec = do
  describe "deck index" do
    it "finds a card by rank" do
      (_.word <$> Deck.card (Rank 2) (Deck.index deck)) `shouldEqual` Just "encontrar"

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

  describe "which card carries the production question" do
    it "the most frequent member of a colliding group" do
      Deck.isCanonical { rank: Rank 1, english: "that", word: "que", example: "" } (Deck.index deck)
        `shouldEqual` true

    it "and not its rarer siblings, which would be the same prompt again" do
      Deck.isCanonical { rank: Rank 3, english: "that", word: "ese", example: "" } (Deck.index deck)
        `shouldEqual` false
      Deck.isCanonical { rank: Rank 4, english: "that", word: "aquel", example: "" } (Deck.index deck)
        `shouldEqual` false

    it "a word that collides with nothing always carries its own" do
      Deck.isCanonical { rank: Rank 2, english: "to find", word: "encontrar", example: "" } (Deck.index deck)
        `shouldEqual` true

    it "exactly one member of every real group carries it" do
      let
        index = Deck.index Spanish.deck
        carried = Array.filter (\c -> Deck.isCanonical c index) Spanish.deck
        englishSides = Array.nub $ map _.english Spanish.deck
      Array.length carried `shouldEqual` Array.length englishSides

    it "leaving the rest recognition-only" do
      let
        index = Deck.index Spanish.deck
        barred = Array.filter (\c -> not $ Deck.isCanonical c index) Spanish.deck
      Array.length barred `shouldEqual` 14

  describe "repairing cards that reached production before the rule" do
    let
      at rank direction box =
        Progress.insert (Rank rank)
          { box, due: epoch, seen: 9, missed: 2, lapses: 1, direction }

    it "sends a non-carrying card back to recognition" do
      let
        stranded = Progress.empty # at 3 Production 2
        fixed = Deck.demoteIneligible (Deck.index deck) stranded
      (_.direction <$> Progress.lookup (Rank 3) fixed.progress) `shouldEqual` Just Recognition
      fixed.demoted `shouldEqual` 1

    it "putting it back where it stood when it graduated" do
      let fixed = Deck.demoteIneligible (Deck.index deck) (Progress.empty # at 3 Production 4)
      (_.box <$> Progress.lookup (Rank 3) fixed.progress) `shouldEqual` Just Scheduler.graduationBox

    it "keeping the history, which did happen" do
      let
        fixed = Deck.demoteIneligible (Deck.index deck) (Progress.empty # at 3 Production 2)
        kept = Progress.lookup (Rank 3) fixed.progress
      (_.seen <$> kept) `shouldEqual` Just 9
      (_.missed <$> kept) `shouldEqual` Just 2
      (_.lapses <$> kept) `shouldEqual` Just 1

    it "leaving the card that does carry its English side alone" do
      let
        ok = Progress.empty # at 1 Production 2
        fixed = Deck.demoteIneligible (Deck.index deck) ok
      (_.direction <$> Progress.lookup (Rank 1) fixed.progress) `shouldEqual` Just Production
      (_.box <$> Progress.lookup (Rank 1) fixed.progress) `shouldEqual` Just 2
      fixed.demoted `shouldEqual` 0

    it "leaving recognition cards alone whether they carry it or not" do
      let fixed = Deck.demoteIneligible (Deck.index deck) (Progress.empty # at 3 Recognition 5)
      (_.box <$> Progress.lookup (Rank 3) fixed.progress) `shouldEqual` Just 5
      fixed.demoted `shouldEqual` 0

    it "counting every one it moved" do
      let
        many = Progress.empty # at 1 Production 3 # at 3 Production 2 # at 4 Production 5
        fixed = Deck.demoteIneligible (Deck.index deck) many
      fixed.demoted `shouldEqual` 2

    it "and doing nothing the second time" do
      let
        idx = Deck.index deck
        once = Deck.demoteIneligible idx (Progress.empty # at 3 Production 2)
        twice = Deck.demoteIneligible idx once.progress
      twice.demoted `shouldEqual` 0
      twice.progress `shouldEqual` once.progress

  describe "against the real deck" do
    it "gathers a synonym group, which is what collisions are now for" do
      Deck.answersFor "there" (Deck.index Spanish.deck)
        `shouldEqual` [ "ahí", "allí", "allá" ]

    it "and gives the disambiguated senses one answer each" do
      -- `that` used to cover six words; each now says which sense it is.
      Deck.answersFor "that (linking clauses)" (Deck.index Spanish.deck) `shouldEqual` [ "que" ]
      Deck.answersFor "that (near you)" (Deck.index Spanish.deck) `shouldEqual` [ "ese" ]
      Deck.answersFor "to be (what it is)" (Deck.index Spanish.deck) `shouldEqual` [ "ser" ]
      Deck.answersFor "to be (how or where it is)" (Deck.index Spanish.deck) `shouldEqual` [ "estar" ]

    it "gives an unambiguous word exactly one answer" do
      Deck.answersFor "to find" (Deck.index Spanish.deck) `shouldEqual` [ "encontrar" ]
