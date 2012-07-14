-- * Introduction
--
--  Bounded channel
-- 
-- * TODOS
--
--    1. check if explicit lock MVar and IORef DList will work better
--    2. check if mutable array will work better that DList
--
module Control.Concurrent.BChan 
  ( BChan
  , newBChan
  , writeBChan
  , readBChan
  , getBChanContents
  , writeList2BChan
  , getBChanSnapshot
  )
  where

import Control.Exception (mask_)
import Prelude hiding (tail, head)
import Control.Concurrent
import Data.DList

import System.IO.Unsafe


data BChan a = BChan QSem QSem (MVar (DList a))

newBChan :: Int -> IO (BChan a)
newBChan n = do
  r <- newQSem 0
  w <- newQSem n
  d <- newMVar empty
  return (BChan r w d)

writeBChan :: BChan a -> a -> IO ()
writeBChan (BChan r w d) v = do
  waitQSem w    -- wait for data place to become avaliable
  mask_ $ do
      modifyMVar_ d (return . (flip snoc v))
      signalQSem r -- mark new data as avaliable 

readBChan :: BChan a -> IO a
readBChan (BChan r w d) = do
  waitQSem r  -- wait for data to become avaliable
  mask_ $ do
      lst <- takeMVar d
      let res = head lst
      putMVar d (tail lst) 
      signalQSem w  -- mark a new place for writer
      return res

getBChanContents :: BChan a -> IO [a]
getBChanContents chan = unsafeInterleaveIO $ do
  x <- readBChan chan
  xs <- getBChanContents chan
  return (x:xs)


writeList2BChan :: [a] -> BChan a -> IO ()
writeList2BChan lst chan = mapM_ (writeBChan chan) lst

getBChanSnapshot :: BChan a -> IO [a]
getBChanSnapshot (BChan _ _ d) =  readMVar d >>= return . toList


