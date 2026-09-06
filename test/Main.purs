module Test.Main
  ( main
  )
  where

import Prelude

import Effect (Effect)
import Test.Flashcards.AccentSpec as AccentSpec
import Test.Flashcards.DeckSpec as DeckSpec
import Test.Flashcards.LanguageSpec as LanguageSpec
import Test.Flashcards.ProgressSpec as ProgressSpec
import Test.Flashcards.SchedulerSpec as SchedulerSpec
import Test.Flashcards.StatsSpec as StatsSpec
import Test.Spec.Runner.Node (runSpecAndExitProcess)
import Test.Spec.Reporter.Console (consoleReporter)

main :: Effect Unit
main = runSpecAndExitProcess [ consoleReporter ] do
  SchedulerSpec.spec
  ProgressSpec.spec
  AccentSpec.spec
  StatsSpec.spec
  DeckSpec.spec
  LanguageSpec.spec
