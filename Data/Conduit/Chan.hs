-- | * Introduction 
--
-- Package provides some conduit sink and sources based on IO Concurrent
-- primitives
--
-- * Primitives
--
-- ** Unbounded
-- *** Infinite channels
--
-- Infinite channels is a plain old concurrent channels that doesn't use
-- any additional information about it's state so it's up to programmer
-- how to stop them and check if the stream is ended. They can be used in
-- case of infinite streams (client-server responces).
--
-- *** EndChannels
--
-- A wrapper over an infinite channel that can mark the end of the stream
-- it doesn't use any additional lock instead of ones used in Concurrent.Chan
-- if the stream is ended Nothing is send over a channel and reciever closes
-- source. N.B. this stream doesn't marked as finished so user can send another
-- message when nobody listens.
--
-- sourceSink supports 2 way of closing:
--
--    1. if one source get Nothing then it sends Nothing to channel in order 
--       to close another sources, 
--    2. Just close without any additional actions in such a way we one can 
--       request closing of any changes
--
-- ** Bounded
--
-- *** BChans
--
-- Higher level synchronization structure that stores information about closing
-- a channel so if user writes to closed channel Nothing happened, and reading
-- from closed channel automatically returns Nothing. This structure have 
-- same caveats with closing as EndChannel has.
--
module Data.Conduit.Chan 
  ( sinkInfiniteChan
  , sourceInfiniteChan
  , sinkEndChan
  , sourceEndChan
  , sinkInfiniteBChan
  , sourceInfiniteBChan
  , sinkEndBChan
  , sourceEndBChan
  , sinkBMChan
  , sourceBMChan
  )
  where

import           Control.Concurrent.Chan
import           Control.Concurrent.BChan
import           Control.Concurrent.BMChan
import           Control.Monad
import           Control.Monad.IO.Class
import           Data.Conduit
import           Data.Maybe

sinkInfiniteChan :: (MonadIO m) => Chan a -> Sink a m ()
sinkInfiniteChan chan = go
  where
    go = do
       mx <- await
       case mx of 
         Just x  -> do 
            liftIO $ writeChan chan x
            go
         Nothing -> return ()

sourceInfiniteChan :: (MonadIO m) => Chan a -> Source m a
sourceInfiniteChan chan = forever $ liftIO (readChan chan) >>= yield

sinkEndChan :: (MonadIO m) => Chan (Maybe a) -> Sink a m ()
sinkEndChan chan = go
  where 
    go = do
      mx <- await 
      liftIO (writeChan chan mx)
      when (isJust mx) go

sourceEndChan :: (MonadIO m) => Bool -> Chan (Maybe a) -> Source m a
sourceEndChan closeAll chan = go
  where
    go = do
      mx <- liftIO $ readChan chan
      case mx of
        Just x -> yield x >> go
        Nothing -> do
          when closeAll $ liftIO (writeChan chan Nothing)
          return ()


sinkInfiniteBChan :: (MonadIO m) => BChan a -> Sink a m ()
sinkInfiniteBChan chan = go
  where
    go = do
       mx <- await
       case mx of 
         Just x  -> do 
            liftIO $ writeBChan chan x
            go
         Nothing -> return ()

sourceInfiniteBChan :: (MonadIO m) => BChan a -> Source m a
sourceInfiniteBChan chan = forever $ liftIO (readBChan chan) >>= yield

sinkEndBChan :: (MonadIO m) => BChan (Maybe a) -> Sink a m ()
sinkEndBChan chan = go
  where 
    go = do
      mx <- await 
      liftIO (writeBChan chan mx)
      when (isJust mx) go

sourceEndBChan :: (MonadIO m) => Bool -> BChan (Maybe a) -> Source m a
sourceEndBChan closeAll chan = go
  where
    go = do
      mx <- liftIO $ readBChan chan
      case mx of
        Just x -> yield x >> go
        Nothing -> do
          when closeAll $ liftIO (writeBChan chan Nothing)
          return ()


sinkBMChan :: (MonadIO m) => BMChan a -> Sink a m ()
sinkBMChan chan = go
  where
    go = do
       mx <- await
       case mx of 
         Just x  -> do 
            written <- liftIO $ writeBMChan chan x
            if written then go
                       else return ()
         Nothing -> do
            liftIO $ closeBMChan chan
            return ()

sourceBMChan :: (MonadIO m) => BMChan a -> Source m a
sourceBMChan chan = addCleanup (const $ liftIO $ closeBMChan chan) go
  where
    go = do 
      mx <- liftIO $ readBMChan chan
      case mx of
        Just x  -> yield x >> go
        Nothing -> return ()
