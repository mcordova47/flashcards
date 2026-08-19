module Test.Main
  ( main
  )
  where

import Prelude

import Effect (Effect)
import Test.Flashcards.SchedulerSpec as SchedulerSpec
import Test.Spec.Runner.Node (runSpecAndExitProcess)
import Test.Spec.Reporter.Console (consoleReporter)

main :: Effect Unit
main = runSpecAndExitProcess [ consoleReporter ] SchedulerSpec.spec
