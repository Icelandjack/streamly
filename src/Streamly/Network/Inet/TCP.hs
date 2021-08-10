-- |
-- Module      : Streamly.Network.Server
-- Copyright   : (c) 2019 Composewell Technologies
--
-- License     : BSD3
-- Maintainer  : streamly@composewell.com
-- Stability   : experimental
-- Portability : GHC
--
-- Combinators to build Inet/TCP clients and servers.
--
-- > import qualified Streamly.Network.Inet.TCP as TCP
--

module Streamly.Network.Inet.TCP
    (
    -- * Accept Connections
      acceptOnAddr
    , acceptOnPort
    , acceptOnPortLocal

    -- * Connect to Servers
    , connect

    -- XXX Expose this as a pipe when we have pipes.
    -- * Transformation
    -- , processBytes

    {-
    -- ** Sink Servers

    -- These abstractions can be applied to any setting where we need to do a
    -- sink processing of multiple streams e.g. output from multiple processes
    -- or data coming from multiple files.

    -- handle connections concurrently using a specified fold
    -- , handleConnections

    -- handle frames concurrently using a specified fold
    , handleFrames

    -- merge frames from all connection into a single stream. Frames can be
    -- created by a specified fold.
    , mergeFrames

    -- * UDP Servers
    , datagrams
    , datagramsOn
    -}
    )
where

import Streamly.Internal.Network.Inet.TCP
