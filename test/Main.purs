module Test.Main
  ( main
  )
  where

import Prelude

import Effect (Effect)
import Test.Flashcards.AccentSpec as AccentSpec
import Test.Flashcards.DeckSpec as DeckSpec
import Test.Flashcards.PageSpec as PageSpec
import Test.Flashcards.ExerciseSpec as ExerciseSpec
import Test.Flashcards.MilestoneSpec as MilestoneSpec
import Test.Flashcards.PayloadSpec as PayloadSpec
import Test.Flashcards.ProgressSpec as ProgressSpec
import Test.Flashcards.SchedulerSpec as SchedulerSpec
import Test.Flashcards.ShiftSpec as ShiftSpec
import Test.Flashcards.StatsSpec as StatsSpec
import Test.Flashcards.SyncSpec as SyncSpec
import Test.Flashcards.VerbsSpec as VerbsSpec
import Test.Spec.Runner.Node (runSpecAndExitProcess)
import Test.Spec.Reporter.Console (consoleReporter)

main :: Effect Unit
main = runSpecAndExitProcess [ consoleReporter ] do
  SchedulerSpec.spec
  ProgressSpec.spec
  AccentSpec.spec
  StatsSpec.spec
  DeckSpec.spec
  PayloadSpec.spec
  PageSpec.spec
  SyncSpec.spec
  MilestoneSpec.spec
  ExerciseSpec.spec
  VerbsSpec.spec
  ShiftSpec.spec
