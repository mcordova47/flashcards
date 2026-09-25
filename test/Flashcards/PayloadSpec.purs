module Test.Flashcards.PayloadSpec
  ( spec
  )
  where

import Prelude

import Data.Array as Array
import Data.Maybe (Maybe(..), fromJust)
import Data.DateTime.Instant (Instant, instant)
import Data.Time.Duration (Milliseconds(..))
import Data.Tuple (fst)
import Flashcards.Deck as Deck
import Flashcards.Payload as Payload
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
  describe "placing a saved payload on the deck" do
    let idx = Deck.index deck

    it "takes a v5 entry at its word, whatever the deck has done since" do
      let adopted = Payload.adopt "current" (Deck.slugAt idx) $ payload (Just "ancient") [ bySlug "ese" ]
      slugsIn adopted.progress `shouldEqual` [ "ese" ]
      adopted.sound `shouldEqual` true
      adopted.migrated `shouldEqual` false

    it "looks an older entry's rank up in the deck" do
      let adopted = Payload.adopt "current" (Deck.slugAt idx) $ payload (Just "current") [ byRank 3 ]
      slugsIn adopted.progress `shouldEqual` [ "ese" ]
      adopted.migrated `shouldEqual` true

    it "and will not vouch for that if the deck has moved since" do
      -- Rank 3 named some other word when this was written, and there is no
      -- way to find out which. The progress is still returned; believing it is
      -- the caller's decision.
      let adopted = Payload.adopt "current" (Deck.slugAt idx) $ payload (Just "ancient") [ byRank 3 ]
      slugsIn adopted.progress `shouldEqual` [ "ese" ]
      adopted.sound `shouldEqual` false

    it "trusts a payload with no fingerprint, which predates every renumbering" do
      let adopted = Payload.adopt "current" (Deck.slugAt idx) $ payload Nothing [ byRank 3 ]
      slugsIn adopted.progress `shouldEqual` [ "ese" ]
      adopted.sound `shouldEqual` true

    it "keeps a slug this deck has never heard of" do
      -- A backup restored onto a bundle that predates a word must not quietly
      -- drop it: nothing reads history except through the deck, so it is inert
      -- until the bundle catches up.
      let adopted = Payload.adopt "current" (Deck.slugAt idx) $ payload (Just "current") [ bySlug "petunia" ]
      slugsIn adopted.progress `shouldEqual` [ "petunia" ]

    it "but drops a rank it has no card at, having nothing to attach it to" do
      let adopted = Payload.adopt "current" (Deck.slugAt idx) $ payload (Just "current") [ byRank 99, byRank 3 ]
      slugsIn adopted.progress `shouldEqual` [ "ese" ]

    it "reports a migration when only some entries need one" do
      let adopted = Payload.adopt "current" (Deck.slugAt idx) $ payload (Just "current") [ bySlug "que", byRank 3 ]
      Array.sort (slugsIn adopted.progress) `shouldEqual` [ "ese", "que" ]
      adopted.migrated `shouldEqual` true

    it "carries the history across intact" do
      let adopted = Payload.adopt "current" (Deck.slugAt idx) $ payload (Just "current") [ byRank 3 ]
      Progress.lookup (Slug "ese") adopted.progress `shouldEqual` Just sample

    -- A page with no history written before v5 has nothing a rank could name,
    -- and says so rather than borrowing someone else's deck to guess with.
    it "places nothing by rank when there is no deck to place it against" do
      let adopted = Payload.adopt "current" (const Nothing) $ payload (Just "current") [ byRank 3 ]
      slugsIn adopted.progress `shouldEqual` []

    it "but still takes anything that named itself" do
      let adopted = Payload.adopt "current" (const Nothing) $ payload (Just "current") [ bySlug "ese" ]
      slugsIn adopted.progress `shouldEqual` [ "ese" ]
      adopted.sound `shouldEqual` true
