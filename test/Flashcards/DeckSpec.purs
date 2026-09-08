module Test.Flashcards.DeckSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..), fromJust)
import Data.Tuple (fst)
import Flashcards.Data.Deck.German as German
import Flashcards.Data.Deck.Spanish as Spanish
import Flashcards.Deck as Deck
import Data.DateTime.Instant (Instant, instant)
import Data.Time.Duration (Milliseconds(..))
import Flashcards.Scheduler as Scheduler
import Flashcards.Types.Card (Card, Rank(..), Slug(..))
import Flashcards.Types.Card as Card
import Flashcards.Types.Direction (Direction(..))
import Flashcards.Types.Progress as Progress
import Partial.Unsafe (unsafePartial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

-- | Two English sides deliberately collide, as they do in the real deck.
deck :: Array Card
deck =
  [ { rank: Rank 1, slug: Slug ("que"), english: "that", word: "que", example: "" }
  , { rank: Rank 2, slug: Slug ("encontrar"), english: "to find", word: "encontrar", example: "" }
  , { rank: Rank 3, slug: Slug ("ese"), english: "that", word: "ese", example: "" }
  , { rank: Rank 4, slug: Slug ("aquel"), english: "that", word: "aquel", example: "" }
  ]

epoch :: Instant
epoch = unsafePartial $ fromJust $ instant $ Milliseconds 0.0

-- | A history distinctive enough to tell which card it landed on.
sample :: Progress.CardProgress
sample = { box: 2, due: epoch, seen: 9, missed: 2, lapses: 1, direction: Recognition }

-- | What v5 writes: the card names itself.
bySlug :: String -> Progress.SavedCard
bySlug slug = { slug: Just (Slug slug), rank: Nothing, progress: sample }

-- | What every version before it wrote: the card names its position, and only
-- | the deck can say which word stood there.
byRank :: Int -> Progress.SavedCard
byRank rank = { slug: Nothing, rank: Just (Rank rank), progress: sample }

payload :: Maybe String -> Array Progress.SavedCard -> Progress.Saved
payload deckPrint cards = { language: Just "es", deck: deckPrint, cards }

slugsIn :: Progress.Progress -> Array String
slugsIn = map (Card.slugToString <<< fst) <<< Progress.entries

spec :: Spec Unit
spec = do
  describe "deck index" do
    it "finds a card by slug" do
      (_.word <$> Deck.card (Slug "encontrar") (Deck.index deck)) `shouldEqual` Just "encontrar"

    it "has nothing for a slug outside the deck" do
      Deck.card (Slug "petunia") (Deck.index deck) `shouldEqual` Nothing

  describe "placing a saved payload on the deck" do
    let idx = Deck.index deck

    it "takes a v5 entry at its word, whatever the deck has done since" do
      let adopted = Deck.adopt "current" idx $ payload (Just "ancient") [ bySlug "ese" ]
      slugsIn adopted.progress `shouldEqual` [ "ese" ]
      adopted.sound `shouldEqual` true
      adopted.migrated `shouldEqual` false

    it "looks an older entry's rank up in the deck" do
      let adopted = Deck.adopt "current" idx $ payload (Just "current") [ byRank 3 ]
      slugsIn adopted.progress `shouldEqual` [ "ese" ]
      adopted.migrated `shouldEqual` true

    it "and will not vouch for that if the deck has moved since" do
      -- Rank 3 named some other word when this was written, and there is no
      -- way to find out which. The progress is still returned; believing it is
      -- the caller's decision.
      let adopted = Deck.adopt "current" idx $ payload (Just "ancient") [ byRank 3 ]
      slugsIn adopted.progress `shouldEqual` [ "ese" ]
      adopted.sound `shouldEqual` false

    it "trusts a payload with no fingerprint, which predates every renumbering" do
      let adopted = Deck.adopt "current" idx $ payload Nothing [ byRank 3 ]
      slugsIn adopted.progress `shouldEqual` [ "ese" ]
      adopted.sound `shouldEqual` true

    it "keeps a slug this deck has never heard of" do
      -- A backup restored onto a bundle that predates a word must not quietly
      -- drop it: nothing reads history except through the deck, so it is inert
      -- until the bundle catches up.
      let adopted = Deck.adopt "current" idx $ payload (Just "current") [ bySlug "petunia" ]
      slugsIn adopted.progress `shouldEqual` [ "petunia" ]

    it "but drops a rank it has no card at, having nothing to attach it to" do
      let adopted = Deck.adopt "current" idx $ payload (Just "current") [ byRank 99, byRank 3 ]
      slugsIn adopted.progress `shouldEqual` [ "ese" ]

    it "reports a migration when only some entries need one" do
      let adopted = Deck.adopt "current" idx $ payload (Just "current") [ bySlug "que", byRank 3 ]
      Array.sort (slugsIn adopted.progress) `shouldEqual` [ "ese", "que" ]
      adopted.migrated `shouldEqual` true

    it "carries the history across intact" do
      let adopted = Deck.adopt "current" idx $ payload (Just "current") [ byRank 3 ]
      Progress.lookup (Slug "ese") adopted.progress `shouldEqual` Just sample

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
      Deck.isCanonical { rank: Rank 1, slug: Slug ("que"), english: "that", word: "que", example: "" } (Deck.index deck)
        `shouldEqual` true

    it "and not its rarer siblings, which would be the same prompt again" do
      Deck.isCanonical { rank: Rank 3, slug: Slug ("ese"), english: "that", word: "ese", example: "" } (Deck.index deck)
        `shouldEqual` false
      Deck.isCanonical { rank: Rank 4, slug: Slug ("aquel"), english: "that", word: "aquel", example: "" } (Deck.index deck)
        `shouldEqual` false

    it "a word that collides with nothing always carries its own" do
      Deck.isCanonical { rank: Rank 2, slug: Slug ("encontrar"), english: "to find", word: "encontrar", example: "" } (Deck.index deck)
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
      at slug direction box =
        Progress.insert (Slug slug)
          { box, due: epoch, seen: 9, missed: 2, lapses: 1, direction }

    it "sends a non-carrying card back to recognition" do
      let
        stranded = Progress.empty # at "ese" Production 2
        fixed = Deck.demoteIneligible (Deck.index deck) stranded
      (_.direction <$> Progress.lookup (Slug "ese") fixed.progress) `shouldEqual` Just Recognition
      fixed.demoted `shouldEqual` 1

    it "putting it back where it stood when it graduated" do
      let fixed = Deck.demoteIneligible (Deck.index deck) (Progress.empty # at "ese" Production 4)
      (_.box <$> Progress.lookup (Slug "ese") fixed.progress) `shouldEqual` Just Scheduler.graduationBox

    it "keeping the history, which did happen" do
      let
        fixed = Deck.demoteIneligible (Deck.index deck) (Progress.empty # at "ese" Production 2)
        kept = Progress.lookup (Slug "ese") fixed.progress
      (_.seen <$> kept) `shouldEqual` Just 9
      (_.missed <$> kept) `shouldEqual` Just 2
      (_.lapses <$> kept) `shouldEqual` Just 1

    it "leaving the card that does carry its English side alone" do
      let
        ok = Progress.empty # at "que" Production 2
        fixed = Deck.demoteIneligible (Deck.index deck) ok
      (_.direction <$> Progress.lookup (Slug "que") fixed.progress) `shouldEqual` Just Production
      (_.box <$> Progress.lookup (Slug "que") fixed.progress) `shouldEqual` Just 2
      fixed.demoted `shouldEqual` 0

    it "leaving recognition cards alone whether they carry it or not" do
      let fixed = Deck.demoteIneligible (Deck.index deck) (Progress.empty # at "ese" Recognition 5)
      (_.box <$> Progress.lookup (Slug "ese") fixed.progress) `shouldEqual` Just 5
      fixed.demoted `shouldEqual` 0

    it "counting every one it moved" do
      let
        many = Progress.empty # at "que" Production 3 # at "ese" Production 2 # at "aquel" Production 5
        fixed = Deck.demoteIneligible (Deck.index deck) many
      fixed.demoted `shouldEqual` 2

    it "and doing nothing the second time" do
      let
        idx = Deck.index deck
        once = Deck.demoteIneligible idx (Progress.empty # at "ese" Production 2)
        twice = Deck.demoteIneligible idx once.progress
      twice.demoted `shouldEqual` 0
      twice.progress `shouldEqual` once.progress

  describe "slugs in the shipped decks" do
    it "defaults to the word itself, verbatim" do
      let card = Array.find (\c -> c.word == "encontrar") Spanish.deck
      (Card.slugToString <<< _.slug <$> card) `shouldEqual` Just "encontrar"

    it "keeps accents, which distinguish words the deck deliberately separates" do
      -- Stripping them would merge this pair, and eleven others in Spanish.
      let slugs = Card.slugToString <<< _.slug <$> Spanish.deck
      Array.elem "este" slugs `shouldEqual` true
      Array.elem "éste" slugs `shouldEqual` true

    it "keeps German pairs apart that differ only by an umlaut" do
      let slugs = Card.slugToString <<< _.slug <$> German.deck
      Array.elem "schon" slugs `shouldEqual` true
      Array.elem "schön" slugs `shouldEqual` true

    it "is unique across every card, which is what progress depends on" do
      let
        slugs = Card.slugToString <<< _.slug <$> Spanish.deck
        germanSlugs = Card.slugToString <<< _.slug <$> German.deck
      Array.length (Array.nub slugs) `shouldEqual` Array.length slugs
      Array.length (Array.nub germanSlugs) `shouldEqual` Array.length germanSlugs

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
