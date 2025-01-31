module Hix where

import Hix.Bootstrap (bootstrapProject)
import Hix.Data.Error (
  Error (..),
  printBootstrapError,
  printEnvError,
  printFatalError,
  printGhciError,
  printNewError,
  printPreprocError,
  )
import Hix.Env (printEnvRunner)
import Hix.Ghci (printGhciCmdline, printGhcidCmdline)
import Hix.Monad (M, runM)
import Hix.New (newProject)
import qualified Hix.Options as Options
import Hix.Options (
  Command (BootstrapCmd, EnvRunner, GhciCmd, GhcidCmd, NewCmd, Preproc),
  GlobalOptions (GlobalOptions),
  Options (Options),
  parseCli,
  )
import Hix.Preproc (preprocess)

handleError ::
  MonadIO m =>
  GlobalOptions ->
  Error ->
  m ()
handleError GlobalOptions {verbose} = \case
  PreprocError err -> printPreprocError err
  EnvError err -> printEnvError err
  GhciError err -> printGhciError err
  NewError err -> printNewError err
  BootstrapError err -> printBootstrapError err
  NoMatch msg | fromMaybe False verbose -> printPreprocError msg
  NoMatch _ -> unit
  Fatal err -> printFatalError err

runCommand :: Command -> M ()
runCommand = \case
  Preproc opts -> preprocess opts
  EnvRunner opts -> printEnvRunner opts.options
  GhcidCmd opts -> printGhcidCmdline opts
  GhciCmd opts -> printGhciCmdline opts
  NewCmd opts -> newProject opts.config
  BootstrapCmd opts -> bootstrapProject opts.config

main :: IO ()
main = do
  Options global cmd <- parseCli
  leftA (handleError global) =<< runM global.cwd (runCommand cmd)
