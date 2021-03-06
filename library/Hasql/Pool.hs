module Hasql.Pool
(
  Pool(..),
  Settings(..),
  acquire,
  release,
  UsageError(..),
  use,
)
where

import Hasql.Pool.Prelude
import qualified Hasql.Connection
import qualified Hasql.Session
import qualified Data.Pool


-- |
-- A pool of connections to DB.
newtype Pool =
  Pool (Data.Pool.Pool (Either Hasql.Connection.ConnectionError Hasql.Connection.Connection))

-- |
-- Settings of the connection pool. Consist of:
-- 
-- * Pool-size.
-- 
-- * Timeout.   
-- An amount of time for which an unused resource is kept open.
-- The smallest acceptable value is 0.5 seconds.
-- 
-- * Connection settings.
-- 
type Settings =
  (Int, NominalDiffTime, Hasql.Connection.Settings)

-- |
-- Given the pool-size, timeout and connection settings
-- create a connection-pool.
acquire :: Settings -> IO Pool
acquire (size, timeout, connectionSettings) =
  fmap Pool $
  Data.Pool.createPool acquire release stripes timeout size
  where
    acquire =
      Hasql.Connection.acquire connectionSettings
    release =
      either (const (pure ())) Hasql.Connection.release
    stripes =
      1

-- |
-- Release the connection-pool.
release :: Pool -> IO ()
release (Pool pool) =
  Data.Pool.destroyAllResources pool

-- |
-- A union over the connection establishment error and the session error.
data UsageError =
  ConnectionError Hasql.Connection.ConnectionError |
  SessionError Hasql.Session.QueryError
  deriving (Show, Eq)

-- |
-- An exception to be thrown inside `Data.Pool.withResource`
-- Its single responsibility is to make sure the resource
-- is not returned to the pool in the case of a ConnectionError
newtype PoolResourceException = PoolResourceException
  { conErr :: Hasql.Connection.ConnectionError
  } deriving (Show)

instance Exception PoolResourceException

-- |
-- Use a connection from the pool to run a session and
-- return the connection to the pool, when finished.
use :: Pool -> Hasql.Session.Session a -> IO (Either UsageError a)
use (Pool pool) session =
  (fmap (either (Left . ConnectionError) (either (Left . SessionError) Right)) $
   Data.Pool.withResource pool $
   const . traverse (Hasql.Session.run session) >>=
   either (throwIO . PoolResourceException)) `catch`
  (\(ex :: PoolResourceException) -> pure (Left (ConnectionError (conErr ex))))
