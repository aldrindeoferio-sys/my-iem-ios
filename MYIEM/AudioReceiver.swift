import Foundation
import AVFoundation
import Network

// MY IEM Native Transport v2
// Design: Audiofusion-style one-way performer receiver + SonoBus-style adaptive
// jitter/deadline handling + MY IEM live-edge stale-packet policy.
// No SonoBus source code is copied; this is an independent implementation.

@MainActor
final class AudioReceiver: ObservableObject {
    @Published var running=false
    @Published var status="Ready"
    @Published var bufferMs=0.0
    @Published var maxBufferMs=0.0
    @Published var received=0
    @Published var sequenceGaps=0
    @Published var latePackets=0
    @Published var reordered=0
    @Published var underruns=0
    @Published var recoveries=0
    @Published var recoveredMs=0.0
    @Published var jitterMs=0.0
    @Published var targetMs=24.0

    private let engine=AVAudioEngine()
    private let player=AVAudioPlayerNode()
    private var connection:NWConnection?
    private var expected:UInt32?
    private var packets:[UInt32:Packet]=[:]
    private var queuedFrames:Int64=0
    private var playedFrames:Int64=0
    private var lastArrival:ContinuousClock.Instant?
    private var jitterEWMA=0.0
    private let clock=ContinuousClock()
    private let rate=48000.0
    private var generation=0
    private var drainTask:Task<Void,Never>?

    private struct Packet {
        let seq:UInt32
        let timestamp:UInt64
        let samples:[Int16]
        let arrival:ContinuousClock.Instant
    }

    func start(host:String, room:String) {
        stop()
        do {
            let s=AVAudioSession.sharedInstance()
            try s.setCategory(.playback,mode:.default,options:[.mixWithOthers])
            try s.setPreferredSampleRate(rate)
            try s.setPreferredIOBufferDuration(0.005)
            try s.setActive(true)

            if player.engine == nil { engine.attach(player) }
            let f=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:rate,channels:1,interleaved:false)!
            engine.disconnectNodeOutput(player)
            engine.connect(player,to:engine.mainMixerNode,format:f)
            try engine.start()
            player.play()

            let p=NWEndpoint.Port(rawValue:10990)!
            let c=NWConnection(host:NWEndpoint.Host(host),port:p,using:.udp)
            connection=c; generation += 1; let g=generation
            c.stateUpdateHandler={ [weak self] state in
                Task { @MainActor in
                    guard let self, g==self.generation else{return}
                    switch state {
                    case .ready:self.status="Receiving UDP • \(room)"
                    case .failed(let e):self.status="Network: \(e.localizedDescription)";self.running=false
                    default:break
                    }
                }
            }
            c.start(queue:DispatchQueue(label:"myiem.udp",qos:.userInteractive))
            running=true;status="Connecting UDP…"
            receiveLoop(g)
            drainTask=Task { [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for:.milliseconds(2))
                    guard let self, self.running else { break }
                    self.drain()
                }
            }
        } catch { status="Audio: \(error.localizedDescription)";running=false }
    }

    func stop(){
        generation += 1; drainTask?.cancel();drainTask=nil
        connection?.cancel();connection=nil
        if player.engine != nil { player.stop() }
        if engine.isRunning { engine.stop() }
        packets.removeAll();expected=nil;queuedFrames=0;playedFrames=0
        running=false;status="Stopped"
    }

    private func receiveLoop(_ g:Int){
        connection?.receiveMessage { [weak self] data,_,_,err in
            guard let self else{return}
            Task { @MainActor in
                guard g==self.generation,self.running else{return}
                if let data { self.ingest(data) }
                if let err { self.status="UDP: \(err.localizedDescription)" }
                self.receiveLoop(g)
            }
        }
    }

    // Datagram: "MIEM" + v1 + flags + headerBytes(LE UInt16=24) +
    // seq LE UInt32 + sender sample timestamp LE UInt64 + frames LE UInt16 +
    // reserved UInt16 + mono Int16LE PCM.
    private func ingest(_ d:Data){
        guard d.count>=24,Array(d.prefix(4))==[77,73,69,77],d[4]==1 else{return}
        let seq=le32(d,8),ts=le64(d,12),frames=Int(le16(d,20))
        guard frames>0,d.count>=24+frames*2 else{return}
        var s=[Int16]();s.reserveCapacity(frames)
        d.withUnsafeBytes { raw in
            for i in 0..<frames { s.append(Int16(littleEndian:raw.loadUnaligned(fromByteOffset:24+i*2,as:Int16.self))) }
        }
        let now=clock.now
        if let la=lastArrival {
            let ms=Double(la.duration(to:now).components.attoseconds)/1e15
            let expectedMs=Double(frames)/rate*1000
            let deviation=abs(ms-expectedMs)
            jitterEWMA=jitterEWMA*.94+deviation*.06
            jitterMs=jitterEWMA
            // SonoBus-inspired principle: adapt gently, bounded for IEM use.
            targetMs=min(45,max(18,18+jitterEWMA*2.2))
        }
        lastArrival=now;received += 1
        if let e=expected {
            if seq < e { latePackets += 1; return }
            if seq > e { reordered += 1 }
        }
        packets[seq]=Packet(seq:seq,timestamp:ts,samples:s,arrival:now)
        if expected==nil { expected=seq }
    }

    private func drain(){
        guard var e=expected else{return}
        let outstanding=max(0,queuedFrames-playedFrames)
        let currentMs=Double(outstanding)/rate*1000
        bufferMs=currentMs;maxBufferMs=max(maxBufferMs,currentMs)

        // Live-edge rule: never speed music up. If native output backlog becomes
        // stale, abandon scheduled stale audio and resume from newest packets.
        if currentMs>90 {
            player.stop();player.play()
            recoveredMs += currentMs
            recoveries += 1
            queuedFrames=playedFrames
        }

        if let p=packets.removeValue(forKey:e) {
            schedule(p.samples);expected=e &+ 1
            return
        }

        // Wait only a bounded jitter deadline for a missing datagram.
        guard let minSeq=packets.keys.min(),minSeq>e else{return}
        let oldest=packets[minSeq]!
        let age=Double(oldest.arrival.duration(to:clock.now).components.attoseconds)/1e15
        if age>=targetMs {
            let gap=minSeq &- e
            sequenceGaps += Int(gap)
            // PLC: schedule one short faded continuation/silence frame rather than
            // waiting for TCP-style retransmission and accumulating latency.
            let n=min(96,oldest.samples.count)
            schedule([Int16](repeating:0,count:n))
            expected=e &+ 1
        }
    }

    private func schedule(_ samples:[Int16]){
        guard !samples.isEmpty,
          let f=AVAudioFormat(commonFormat:.pcmFormatFloat32,sampleRate:rate,channels:1,interleaved:false),
          let b=AVAudioPCMBuffer(pcmFormat:f,frameCapacity:AVAudioFrameCount(samples.count)),
          let dst=b.floatChannelData?[0] else{return}
        b.frameLength=AVAudioFrameCount(samples.count)
        for i in samples.indices { dst[i]=Float(samples[i])/32768.0 }
        let n=Int64(samples.count);queuedFrames += n
        player.scheduleBuffer(b,completionCallbackType:.dataPlayedBack){ [weak self] _ in
            Task { @MainActor in
                guard let self else{return}
                self.playedFrames += n
                let q=max(0,self.queuedFrames-self.playedFrames)
                self.bufferMs=Double(q)/self.rate*1000
                if q==0 && self.running { self.underruns += 1 }
            }
        }
    }

    private func le16(_ d:Data,_ o:Int)->UInt16 { d.withUnsafeBytes{UInt16(littleEndian:$0.loadUnaligned(fromByteOffset:o,as:UInt16.self))} }
    private func le32(_ d:Data,_ o:Int)->UInt32 { d.withUnsafeBytes{UInt32(littleEndian:$0.loadUnaligned(fromByteOffset:o,as:UInt32.self))} }
    private func le64(_ d:Data,_ o:Int)->UInt64 { d.withUnsafeBytes{UInt64(littleEndian:$0.loadUnaligned(fromByteOffset:o,as:UInt64.self))} }
}
