import Criterion.Main (default

iochan nR nW n = do
  ch <- newBMChan
  lock <- newEmptyMVar
  forkIO $ runResourceT $ sourceList [1..n] $$ sinkBMChan ch
  forkIO $ do
    runResourceT $ sourceBMChan ch $$ consume
    putMVar lock ()
  _ <- takeMVar



main = defaultMain [
        bgroup "iochan" [ bench "10" $ nfIO iochan 10
                        , bench "100" $ nfIO iochan 100
                        , banch "1000" $ nfIO iochan 1000
                        ]
      ]
