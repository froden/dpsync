{-# LANGUAGE OverloadedStrings #-}

module Sync2 where

import Network.HTTP.Conduit
import Control.Monad.Error
import Control.Monad.Trans.Resource
import Control.Monad.Reader (ReaderT, ask, runReaderT)
import Data.Map (Map)
import qualified Data.Map as Map
import Data.Set (Set)
import qualified Data.Set as Set
import System.FilePath.Posix
import System.Directory
import Data.List
import Data.Maybe
import Control.Exception
import Text.Read (readMaybe)

import Api
import qualified ApiTypes as DP
import Http (AccessToken)
import File2
import Oauth
import Sync (handleTokenRefresh)

type CSRFToken = String
type ApiAction a = ReaderT (Manager, AccessToken, CSRFToken, DP.Mailbox) (ResourceT IO) a

data SyncState = SyncState {localSyncState :: Set File, remoteSyncState :: Map File RemoteFile} deriving (Show, Read)

syncDirName :: String
syncDirName = "Digipostarkiv"

readSyncState :: FilePath -> IO SyncState
readSyncState syncFile = do
        r <- try (readFile syncFile) :: IO (Either IOException String)
        case r of
            Right content -> return $ fromMaybe emptyState (readMaybe content)
            Left _ -> return emptyState
    where emptyState = SyncState Set.empty Map.empty

writeSyncState :: FilePath -> SyncState -> IO ()
writeSyncState syncFile state = writeFile syncFile (show state)

getRemoteState :: ApiAction (Map File RemoteFile)
getRemoteState = do
    (_, _, _, mbox) <- ask
    let mboxFolders = (DP.folder . DP.folders) mbox
    contents <- mapM getFolderContents mboxFolders
    return $ Map.unions contents
  where
    getFolderContents :: DP.Folder -> ApiAction (Map File RemoteFile)
    getFolderContents folder = do
        (manager, aToken, _, _) <- ask
        folderLink <- liftIO $ linkOrException "self" $ DP.folderLinks folder
        fullFolder <- liftResourceT $ getFolder aToken manager folderLink
        let folderDocuments = filter DP.uploaded (DP.documentInFolder fullFolder)
        let dir = (dirFromFolder folder, remoteDirFromFolder folder)
        let files = map (mapFileToRemoteFile folder) folderDocuments
        return $ Map.fromList (dir : files)
      where
        mapFileToRemoteFile fldr doc = let file = fileFromFolderDoc fldr doc
                                         in (file, RemoteFile file fldr doc)

getDirContents :: FilePath -> IO [FilePath]
getDirContents dirPath = do
        names <- getDirectoryContents dirPath
        return $ filter (not . specialFiles) names
    where specialFiles f = "." `isPrefixOf` f || f `elem` [".", ".."]

--todo lag en funksjon som kun tar inn syncdir og gjør alle pather relative til den
--lag en ny indre funksjon som gjør rekursjon
--hvis ikke får vi med ./ i resultatet...
getLocalState :: FilePath -> FilePath -> IO (Set File)
getLocalState syncDirPath dirPath = do
        properNames <- getDirContents dirPath
        content <- forM properNames $ \name -> do
            let subPath = dirPath </> name
            isDirectory <- doesDirectoryExist subPath
            if isDirectory
                then getLocalState syncDirPath subPath
                else return $ Set.singleton (File $ makeRelative syncDirPath subPath)
        let contentSet = Set.unions content
        let dir = Dir $ addTrailingPathSeparator (makeRelative syncDirPath dirPath)
        return $ Set.insert dir contentSet

initLocalState :: IO (FilePath, FilePath, SyncState, Set File)
initLocalState = do
    syncDir <- getOrCreateSyncDir
    let syncFile = getSyncFile syncDir
    previousState <- readSyncState syncFile
    localState <- getLocalState syncDir syncDir
    return (syncDir, syncFile, previousState, localState)

sync :: IO ()
sync = loadAccessToken >>= handleTokenRefresh sync'

sync' :: AccessToken -> IO ()
sync' token = do
    (syncDir, syncFile, previousState, localFiles) <- initLocalState
    runResourceT $ do
        manager <- liftIO $ newManager conduitManagerSettings
        (root, _, mbox) <- getAccount manager token
        flip runReaderT (manager, token, DP.csrfToken root, mbox) $ do
            remoteState <- getRemoteState
            let remoteFiles = getFileSetFromMap remoteState
            let previousRemoteState = remoteSyncState previousState
            let previousRemoteFiles = getFileSetFromMap previousRemoteState
            let previousLocalFiles = localSyncState previousState
            liftIO $ print remoteFiles
            liftIO $ print previousRemoteFiles
            liftIO $ print localFiles
            liftIO $ print previousLocalFiles
            let localChanges = computeChanges localFiles previousLocalFiles
            let remoteChanges = computeChanges remoteFiles previousRemoteFiles
            let changesToApplyLocal = computeChangesToApply remoteChanges localChanges
            let changesToApplyRemote = computeChangesToApply localChanges remoteChanges
            liftIO $ print changesToApplyLocal
            liftIO $ print changesToApplyRemote
            return ()

getUserSyncDir :: IO FilePath
getUserSyncDir = do
    homedir <- getHomeDirectory
    return $ combine homedir syncDirName

getOrCreateSyncDir :: IO FilePath
getOrCreateSyncDir = do
    syncDir <- getUserSyncDir
    createDirectoryIfMissing True syncDir
    return syncDir

getSyncFile :: FilePath -> FilePath
getSyncFile syncDir = combine syncDir ".sync"

debugLog :: String -> IO ()
debugLog = putStrLn
-- debugLog _ = return ()