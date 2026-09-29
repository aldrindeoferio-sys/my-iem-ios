import Foundation
import AVFoundation

@MainActor
final class AudioReceiver: ObservableObject {
    @Published var running=false
    @Published var status="Ready"
    @Published var bufferMs=0.0
    @Published var maxBufferMs=0.0
    @Published var received=0
    @Published var sequenceGaps=0
    @Published var underruns=0
    @Published var recoveries=0
    @Published var recoveredMs=0.0

    private let engine=AVAudioEngine()
    private let player=AVAudioPlayerNode()
    private var task:URLSessionWebSocketTask?
    private var expected:UInt32?
    private var queuedFrames:Int64=0
    private var playedFrames:Int64=0
    private let rate=48000.0
    private let targetFrames:Int64=2880 // 60 ms
    private let staleFrames:Int64=5760  // 120 ms
    private var generation=0

    func start(host:String, room:String) {
        stop()
        do {
            let session=AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode:.default, options:[])
            try session.setPreferredSampleRate(rate)
            try session.setPreferredIOBufferDuration(0.005)
            try session.setActive(true)

            engine.attach(player)
            let fmt=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:rate,channels:1,interleaved:false)!
            engine.connect(player,to:engine.mainMixerNode,format:fmt)
            try engine.start()
            player.play()

            // Current MY IEM server is HTTPS/WSS on 3443.
            guard let url=URL(string:"wss://\(host):3443/?role=receiver&room=\(room.addingPercentEncoding(withAllowedCharacters:.urlQueryAllowed) ?? room)") else { return }
            let sessionConfig=URLSessionConfiguration.default
            sessionConfig.waitsForConnectivity=true
            let ws=URLSession(configuration:sessionConfig,delegate:TrustLocalDelegate(),delegateQueue:nil)
            task=ws.webSocketTask(with:url)
            task?.resume()
            running=true;status="Connecting…";generation += 1
            receiveLoop(gen:generation)
        } catch {
            status="Audio error: \(error.localizedDescription)"
            running=false
        }
    }

    func stop() {
        generation += 1
        task?.cancel(with:.goingAway,reason:nil);task=nil
        if player.engine != nil { player.stop() }
        if engine.isRunning { engine.stop() }
        running=false
        expected=nil;queuedFrames=0;playedFrames=0
        status="Stopped"
    }

    private func receiveLoop(gen:Int) {
        task?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                guard gen == self.generation, self.running else { return }
                switch result {
                case .failure(let e):
                    self.status="Network: \(e.localizedDescription)"
                    self.running=false
                case .success(let message):
                    self.status="Receiving"
                    if case .data(let d)=message { self.consume(d) }
                    self.receiveLoop(gen:gen)
                }
            }
        }
    }

    private func consume(_ data:Data) {
        guard data.count > 24 else { return }
        received += 1

        let seq:UInt32=data.withUnsafeBytes { raw in
            UInt32(littleEndian:raw.loadUnaligned(fromByteOffset:0,as:UInt32.self))
        }
        if let e=expected, seq != e {
            let delta=seq &- e
            if delta < 0x80000000 { sequenceGaps += Int(delta) }
        }
        expected=seq &+ 1

        let payload=data.dropFirst(24)
        let samples=payload.count/2
        guard samples>0 else { return }

        let outstanding=max(0,queuedFrames-playedFrames)
        if outstanding + Int64(samples) > staleFrames {
            // Native live-edge policy: discard stale queued buffers and restart
            // close to the newest packet. Pitch never changes.
            let old=outstanding
            player.stop()
            player.play()
            queuedFrames=playedFrames
            recoveries += 1
            recoveredMs += Double(old)/rate*1000
        }

        guard let fmt=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:rate,channels:1,interleaved:false),
              let b=AVAudioPCMBuffer(pcmFormat:fmt,frameCapacity:AVAudioFrameCount(samples)) else { return }
        b.frameLength=AVAudioFrameCount(samples)
        guard let dst=b.floatChannelData?[0] else { return }
        payload.withUnsafeBytes { raw in
            for i in 0..<samples {
                let s=Int16(littleEndian:raw.loadUnaligned(fromByteOffset:i*2,as:Int16.self))
                dst[i]=Float(s)/32768.0
            }
        }
        queuedFrames += Int64(samples)
        let count=Int64(samples)
        player.scheduleBuffer(b,completionCallbackType:.dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.playedFrames += count
                self.updateMeters()
            }
        }
        updateMeters()
    }

    private func updateMeters() {
        let outstanding=max(0,queuedFrames-playedFrames)
        bufferMs=Double(outstanding)/rate*1000
        maxBufferMs=max(maxBufferMs,bufferMs)
        if running && outstanding == 0 && received > 2 { underruns += 1 }
    }
}

private final class TrustLocalDelegate:NSObject,URLSessionDelegate {
    func urlSession(_ session:URLSession,didReceive challenge:URLAuthenticationChallenge,completionHandler:@escaping(URLSession.AuthChallengeDisposition,URLCredential?)->Void) {
        // Development/TestFlight LAN build: accept the current self-signed MY IEM server cert.
        // Replace with certificate pinning before production distribution.
        if let trust=challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential,URLCredential(trust:trust))
        } else { completionHandler(.performDefaultHandling,nil) }
    }
}
