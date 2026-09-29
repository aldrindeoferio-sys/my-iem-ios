# MY IEM iOS

Native iPhone receiver for the MY IEM low-latency monitoring project.

## v0.1 receiver
- SwiftUI interface
- Native AVAudioSession / AVAudioEngine output at 48 kHz
- Native WebSocket client compatible with the current MY IEM WSS sender/server
- 24-byte MIEM-WEB/1 packet header parsing
- Int16 mono PCM playback
- bounded live jitter FIFO
- stale-audio rejection instead of speed-up playback
- sequence gap / underrun / recovery / buffer diagnostics
- background audio capability
- local-network permission
- GitHub Actions Xcode build validation

This first build intentionally keeps the current server transport so native iOS vs Safari can be compared before changing transport.
