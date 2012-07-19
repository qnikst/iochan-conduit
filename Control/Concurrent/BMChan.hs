module Control.Concurrent.BMChan
  ( BMChan
  , newBMChan
  , readBMChan
  , writeBMChan
  , isClosedBMChan
  , closeBMChan
  )
  where

import           Control.Concurrent
import           Data.IORef
import           Data.Vector.Mutable (IOVector)
import qualified Data.Vector.Mutable as V
import           Prelude             hiding (head, tail)

data BMChan a = BMChan
      { isClosed :: IORef Bool
      , readQ    :: QSem
      , writeQ   :: QSem
      , lock     :: MVar ()
      , values   :: IOVector a
      , readN    :: IORef Int
      , writeN   :: IORef Int
      , inc      :: IORef Int -> IO ()
      }

newBMChan :: Int -> IO (BMChan a)
newBMChan n = do
  c <- newIORef False
  r <- newQSem 0
  w <- newQSem n
  l <- newMVar ()
  v <- V.new   n
  ir <- newIORef 0
  iw <- newIORef 0
  let inc c = modifyIORef c (\x -> (x + 1) `mod` n) 
--  v <- newIORef empty
  return $ BMChan c r w l v ir iw inc



-- | N.B. closed channel break property
--        readers avail + write avail == buffer size
readBMChan :: BMChan a -> IO (Maybe a)
readBMChan ch = do
  waitQSem (readQ ch)
  withMVar (lock  ch) $ const $ do
    isC <- readIORef (isClosed ch)
    iR  <- readIORef (readN ch)
    iW  <- readIORef (writeN ch)
    if isC -- if channel is closed we have 2 situations
       then if iR == iW 
           then do                                   -- if list finished: we should signal all readers
             signalQSem (readQ ch)
             return Nothing
           else do
             inc ch (readN ch)
             v <- V.read (values ch) iR
             signalQSem (writeQ ch)
             return (Just v)
       else do
           inc ch (readN ch)
           v <- V.read (values ch) iR
           signalQSem (writeQ ch)                                      -- if channel is open then work as is
           return (Just v)

writeBMChan :: BMChan a -> a -> IO ()
writeBMChan ch val = do
  waitQSem (writeQ ch)
  withMVar (lock ch) $ const $ do
    isC <- readIORef (isClosed ch)
    if isC then signalQSem (writeQ ch)
           else do
            iW <- readIORef (writeN ch)
            V.write (values ch) iW val
            inc ch (writeN ch)
            signalQSem (readQ ch)


closeBMChan :: BMChan a -> IO ()
closeBMChan ch =
  withMVar (lock ch) $ const $ do
    writeIORef (isClosed ch) True
    signalQSem (readQ ch)
    signalQSem (writeQ ch)

isClosedBMChan :: BMChan a -> IO Bool
isClosedBMChan ch = withMVar (lock ch) $ const $ readIORef (isClosed ch)

