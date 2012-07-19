module Control.Concurrent.BMChan
  ( BMChan
  , newBMChan
  , readBMChan
  , writeBMChan
  , isClosedBMChan 
  , closeBMChan
  )
  where

import Prelude hiding (head, tail)
import Data.DList
import Data.IORef
import Control.Concurrent

data BMChan a = BMChan 
      { isClosed :: IORef Bool
      , readQ    :: QSem  
      , writeQ   :: QSem
      , lock     :: MVar ()
      , values   :: IORef (DList a)
      }

newBMChan :: Int -> IO (BMChan a)
newBMChan n = do
  c <- newIORef False
  r <- newQSem 0
  w <- newQSem n
  l <- newMVar ()
  v <- newIORef empty
  return $ BMChan c r w l v



-- | N.B. closed channel break property 
--        readers avail + write avail == buffer size
readBMChan :: BMChan a -> IO (Maybe a)
readBMChan (BMChan c r w lock v) = do
  waitQSem r
  withMVar lock $ const $ do
    l <-   readIORef v
    isC <- readIORef c
    (v',r) <- if isC then -- if channel is closed we have 2 situations
                 case toList l of
                    []    -> cleanup                                -- if list finished: we should signal all readers
                    (x:_) -> signalQSem w >> return (tail l,Just x) -- otherwise work as in normal situation
               else normal l                                        -- if channel is open then work as is
    writeIORef v v'
    return r
  where normal l = do
          let res = head l              -- read list head
          signalQSem w                  -- signal writer
          return (tail l, Just res)     -- update
        cleanup = do
          signalQSem r                  -- wake up another reader
          return (empty, Nothing)

writeBMChan :: BMChan a -> a -> IO ()
writeBMChan (BMChan c r w lock v) val = do
  waitQSem w
  withMVar  lock $ const $ do
    l <- readIORef v
    isC <- readIORef c
    if isC then signalQSem w
           else do signalQSem r >> modifyIORef v (`snoc` val)


closeBMChan :: BMChan a -> IO ()
closeBMChan (BMChan c r w lock v) =
  withMVar lock $ const $ do
    writeIORef c True
    signalQSem r
    signalQSem w

isClosedBMChan :: BMChan a -> IO Bool
isClosedBMChan ch = withMVar (lock ch) $ const $ readIORef (isClosed ch)

