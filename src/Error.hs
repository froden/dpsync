{-# LANGUAGE DeriveDataTypeable #-}

module Error where

import Control.Exception
import Network.HTTP.Conduit
import Data.Typeable

data SyncError = NotAuthenticated | HttpFailed HttpException | Unhandled SomeException deriving (Show, Typeable)

instance Exception SyncError
