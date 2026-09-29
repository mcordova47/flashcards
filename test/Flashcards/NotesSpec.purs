module Test.Flashcards.NotesSpec
  ( spec
  )
  where

import Prelude

import Data.Argonaut.Core (stringify)
import Data.Argonaut.Parser (jsonParser)
import Data.DateTime.Instant (Instant, instant)
import Data.Either (Either(..), isLeft)
import Data.Maybe (fromJust)
import Data.Time.Duration (Milliseconds(..))
import Flashcards.Notes (Note)
import Flashcards.Notes as Notes
import Partial.Unsafe (unsafePartial)
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual, shouldSatisfy)

at :: Number -> Instant
at ms = unsafePartial $ fromJust $ instant $ Milliseconds ms

-- | 2023-11-14 22:13:20 UTC, and a morning a day later, so both a two-digit
-- | and a padded hour are in play.
first :: Note
first = { at: at 1700000000000.0, context: "/verbs · porpara.means · by phone", text: "the hint is confusing" }

second :: Note
second = { at: at 1700031000000.0, context: "/es · querer · recognition", text: "two lines\nof it" }

parse :: String -> Either String (Array Note)
parse raw = case jsonParser raw of
  Left e -> Left e
  Right json -> case Notes.fromJson json of
    Left e -> Left (show e)
    Right notes -> Right notes

spec :: Spec Unit
spec = describe "notes" do
  describe "the saved format" do
    it "round-trips, line breaks and all" do
      parse (stringify $ Notes.toJson [ first, second ]) `shouldEqual` Right [ first, second ]

    it "round-trips an empty list" do
      parse (stringify $ Notes.toJson []) `shouldEqual` Right []

    -- A newer app wrote it, and reading it as this one would lose whatever
    -- it added.
    it "refuses a version it does not know" do
      parse """{"version":2,"notes":[]}""" `shouldSatisfy` isLeft

    it "refuses a list with no version at all" do
      parse """{"notes":[]}""" `shouldSatisfy` isLeft

    it "refuses a note missing its text" do
      parse """{"version":1,"notes":[{"at":0,"context":""}]}""" `shouldSatisfy` isLeft

  describe "the stamp" do
    it "is in UTC and says so" do
      Notes.stamp first.at `shouldEqual` "2023-11-14 22:13 UTC"

    it "pads the hour and the minute" do
      Notes.stamp second.at `shouldEqual` "2023-11-15 06:50 UTC"

  describe "the export" do
    it "is every note, oldest first, each under its stamp and context" do
      Notes.export [ first, second ] `shouldEqual`
        ( "2023-11-14 22:13 UTC · /verbs · porpara.means · by phone\n"
            <> "the hint is confusing\n\n"
            <> "2023-11-15 06:50 UTC · /es · querer · recognition\n"
            <> "two lines\nof it"
        )

    it "is empty for no notes" do
      Notes.export [] `shouldEqual` ""

  describe "what is left to deliver" do
    it "is everything, when nothing has gone" do
      Notes.undelivered 0 [ first, second ] `shouldEqual` [ first, second ]

    it "is what came after the ones that went" do
      Notes.undelivered 1 [ first, second ] `shouldEqual` [ second ]

    it "is nothing, once they all have" do
      Notes.undelivered 2 [ first, second ] `shouldEqual` []

    -- Counted against some other list. Sending them all again costs a
    -- request; sending none would strand them.
    it "is everything again, when the count is more than the list holds" do
      Notes.undelivered 3 [ first, second ] `shouldEqual` [ first, second ]
