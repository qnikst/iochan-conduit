module Control.Concurrent.BMChan
  ( newBMChan
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
      , values   :: MVar (DList a)
      }

newBMChan :: Int -> IO (BMChan a)
newBMChan n = do
  c <- newIORef False
  r <- newQSem 0
  w <- newQSem n
  v <- newMVar empty
  return $ BMChan c r w v



-- | N.B. closed channel break property 
--        readers avail + write avail == buffer size
readBMChan :: BMChan a -> IO (Maybe a)
readBMChan (BMChan c r w v) = do
  waitQSem r
  modifyMVar v $ \l -> do
    isC <- readIORef c
    if isC then -- if channel is closed we have 2 situations
              case toList l of
                [] -> cleanup r                                 -- if list finished: we should signal all readers
                (x:_) -> signalQSem w >> return (tail l,Just x) -- otherwise work as in normal situation
           else normal l w         -- if channel is open then work as is
  where normal l w = do
          let res = head l              -- read list head
          signalQSem w                  -- signal writer
          return (tail l, Just res)     -- update
        cleanup r = do
          signalQSem r                  -- wake up another reader
          return (empty, Nothing)

writeBMChan :: BMChan a -> a -> IO ()
writeBMChan (BMChan c r w v) val = do
  waitQSem w
  modifyMVar v $ \l -> do
    isC <- readIORef c
    if isC then signalQSem w >> return (l,())
           else do
            signalQSem r
            return (l `snoc` val,())


closeBMChan :: BMChan a -> IO ()
closeBMChan (BMChan c r w v) =
  withMVar v $ \l -> do -- take a lock of structure
    writeIORef c True
    case toList l of
      [] -> signalQSem r
      _  -> return ()
    signalQSem w                     -- wake up writer

isClosedBMChan :: BMChan a -> IO Bool
isClosedBMChan ch = withMVar (values ch) $ const $ readIORef (isClosed ch)

