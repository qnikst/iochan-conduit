import Criterion
import Criterion.Main (defaultMain)
import Control.Monad
import Control.Concurrent
import Control.Concurrent.BMChan
-- import Control.Concurrent.MChan
import Control.Concurrent.STM
import Data.Maybe
import Data.Conduit
import Data.Conduit.List as CL
import Data.Conduit.Chan
import Data.Conduit.TMChan

-- | Run IO channel with concrete number of readers and writers
-- finishes when all data is sent
iochan nR nW n = do
  ch <- newBMChan 16
  lock <- newQSemN 0
  start_readers <- newEmptyMVar
  forkIO $ runResourceT $ sourceList [1..n] $$ sinkBMChan ch
  forM_ [1..nR] $ 
      const . forkIO $ do
        _ <- readMVar start_readers -- start thread
        runResourceT $ sourceBMChan ch $= CL.map f $$ consume
        signalQSemN lock 1
  putMVar start_readers ()
  waitQSemN lock nR
  return ()
  where f = exp . log . exp . log . exp . log . exp . log . exp . log

iochan2 nR nW n = do
  ch <- newChan
  lock <- newQSemN 0
  forkIO $ do
    runResourceT $ sourceList [1..n] $= CL.map Just $$ sinkEndChan ch
    writeChan ch Nothing
  forM_ [1..nR] $ 
      const . forkIO $ do
        runResourceT $ sourceEndChan True ch $= CL.map (f . fromJust) $$ consume
        signalQSemN lock 1
  waitQSemN lock nR
  return ()
  where f = exp . log . exp . log . exp . log . exp . log . exp . log

stmchan nR nW n = do
  ch <- atomically $ newTBMChan 16
  lock <- newQSemN 0
  forkIO $ runResourceT $ sourceList [1..n] $$ sinkTBMChan ch
  forM_ [1..nR] $ 
      const . forkIO $ do
        runResourceT $ sourceTBMChan ch $= CL.map f $$ consume
        signalQSemN lock 1
  waitQSemN lock nR
  return ()
  where f = exp . log . exp . log . exp . log . exp . log . exp . log

main = defaultMain [
        bgroup "iochan" [ bench "1000"    $ nfIO $ iochan 1 1   10000
                        , bench "1000:2"  $ nfIO $ iochan 1 2   10000
                        , bench "1000:10" $ nfIO $ iochan 1 10  10000
                        ]
      ,
        bgroup "iochan2"[ bench "1000"    $ nfIO $ iochan2 1 1   10000
                        , bench "1000:2"  $ nfIO $ iochan2 1 2   10000
                        , bench "1000:10" $ nfIO $ iochan2 1 10  10000
                        ]
      , bgroup "stm"    [ bench "1000"    $ nfIO $ stmchan 1 1  10000
                        , bench "1000:2"  $ nfIO $ stmchan 1 2  10000
                        , bench "1000:10" $ nfIO $ stmchan 1 10 10000
                        ]
      ]
