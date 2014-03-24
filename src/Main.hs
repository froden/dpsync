{-# LANGUAGE OverloadedStrings #-}

module Main where

import Network.HTTP.Conduit
import Network.HTTP.Types.Status
import Control.Monad.Error
import Control.Monad.Trans.Resource
import Control.Monad.Trans.Either
import System.FilePath.Posix
import Data.List
import Control.Concurrent
import System.Directory
import System.IO
import Control.Exception

import Api
import Root
import Link
import qualified Account as A
import qualified Document as D
import qualified File as F
import qualified Config as C
import Oauth
import Http (Session)

main :: IO ()
main = do
    token <- runResourceT login
    userHome <- getHomeDirectory
    let config = C.defaultConfig userHome
    putStrLn $ "Using syncDir: " ++ C.syncDir config
    F.createSyncDir $ C.syncDir config
    catch (sync config (Right token)) handleError

loop :: C.Config -> Session -> IO ()
loop config session = do
    sync config session
    threadDelay $ syncInterval (C.interval config)
    loop config session

guiSync :: IO (SyncResult ())
guiSync = runEitherT $ do
    userHome <- liftIO getHomeDirectory
    let config = C.defaultConfig userHome
    liftIO $ F.createSyncDir $ C.syncDir config
    at <- liftIO loadAccessToken
    token <- case at of
            Nothing -> left NotAuthenticated
            Just t -> right t
    res <- liftIO $ try (sync config (Right token))
    case res of
        Left (StatusCodeException (Status 403 _) _ _) -> do
            liftIO $ putStrLn "403 status"
            left NotAuthenticated
        Left (StatusCodeException (Status 401 _) _ _) -> do
            liftIO $ putStrLn "401 status"
            left NotAuthenticated
        Left e -> left $ HttpFailed e
        Right _ -> right ()

sync :: C.Config -> Session -> IO ()
sync config session = runResourceT $ do
    manager <- liftIO $ newManager conduitManagerSettings
    (root, account) <- getAccount manager session
    archiveLink <- A.archiveLink account
    documents <- getDocs manager session archiveLink
    let syncDir = C.syncDir config
    let syncFile = F.syncFile syncDir
    files <- liftIO $ F.existingFiles syncDir
    lastState <- liftIO $ F.readSyncFile syncFile
    let (docsToDownload, newFiles, deletedFiles) = F.syncDiff lastState files documents
    liftIO $ void $ mapM debugLog [
                            "download: [" ++ intercalate ", " (map D.filename docsToDownload) ++ "]",
                            "upload: [" ++ intercalate ", " newFiles ++ "]",
                            "deleted: [" ++ intercalate ", " deletedFiles ++ "]" ]
    downloadAll session manager syncDir docsToDownload
    let Just uploadLink = linkWithRel "upload_document" $ A.link account
    uploadAll session manager uploadLink (csrfToken root) (map (combine syncDir) newFiles)
    liftIO $ F.deleteAll syncDir deletedFiles
    newState <- liftIO $ F.existingFiles syncDir
    liftIO $ F.writeSyncFile syncFile newState
    liftIO $ debugLog "Finished"

getUsername :: IO String
getUsername = getInput "Fødselsnummer" True

getPassword :: IO String
getPassword = getInput "Passord" False

getInput :: String -> Bool -> IO String
getInput label echo = do
    putStr $ label ++ ": "
    hFlush stdout
    input <- withEcho echo getLine
    unless echo $ putChar '\n'
    return input

withEcho :: Bool -> IO a -> IO a
withEcho echo action = do
  old <- hGetEcho stdin
  bracket_ (hSetEcho stdin echo) (hSetEcho stdin old) action

syncInterval :: Maybe Int -> Int
syncInterval Nothing = 10 * 1000000
syncInterval (Just interval)
    | interval < 5 = 5 * seconds
    | otherwise = interval * seconds
        where seconds = 1000000

handleError :: HttpException -> IO ()
handleError (StatusCodeException (Status 403 _) _ _) = putStrLn "Feil fødselsnummer eller passord"
handleError e = throwIO e

debugLog :: String -> IO ()
debugLog = putStrLn
