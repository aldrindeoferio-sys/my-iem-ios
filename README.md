# MY IEM iOS — Native Hybrid Receiver v0.2

A new receiver architecture combining the strongest *design ideas* from three systems without copying third-party source code:

1. **Audiofusion-style IEM topology** — laptop/soundboard is the broadcaster; phones are lightweight performer receivers over a dedicated Wi-Fi LAN.
2. **SonoBus-style real-time principles** — direct packet audio, bounded/adaptive receive jitter, packet sequence handling, PCM at 48 kHz, visible network/audio diagnostics. SonoBus is GPLv3, so its implementation is **not copied** into this repository.
3. **MY IEM lessons** — fixed pitch only, strict live-edge policy, stale audio is discarded rather than played fast, and latency maxima are visible.

## v0.2 transport

The old WSS/TCP audio path is replaced by native UDP datagrams on port **10990**.

Packet v1:
- 0..3: ASCII MIEM
- 4: version = 1
- 5: flags
- 6..7: header bytes = 24
- 8..11: UInt32 sequence, little endian
- 12..19: UInt64 sender sample timestamp, little endian
- 20..21: UInt16 frame count
- 22..23: reserved
- 24..: mono signed Int16 little-endian PCM

Receiver:
- AVAudioSession playback at 48 kHz
- preferred 5 ms device I/O buffer
- AVAudioEngine/AVAudioPlayerNode
- adaptive jitter deadline, bounded 18–45 ms
- out-of-order packet map
- missing-packet deadline + short PLC silence
- late packet rejection
- no retransmission wait
- no variable-speed catch-up
- hard live-edge recovery only if native scheduled output exceeds 90 ms
- background audio mode

## Important

v0.2 requires a matching **UDP sender**. The previous browser WSS sender does not emit this new datagram protocol. That sender is the next half of the system.

For stage use, connect the sender computer to the access point by Ethernet when possible and keep performers on a dedicated 5/6 GHz Wi-Fi network.
