import SwiftUI

struct ContentView: View {
    @EnvironmentObject var r: AudioReceiver
    @State private var host = "192.168.0.193"
    @State private var room = "stage"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    Text("MY IEM").font(.largeTitle.bold())
                    Text("Native iOS Receiver • v0.1").foregroundStyle(.secondary)
                    HStack {
                        TextField("Sender IP", text: $host).textFieldStyle(.roundedBorder)
                        TextField("Room", text: $room).textFieldStyle(.roundedBorder)
                    }
                    Button(r.running ? "STOP" : "START") {
                        r.running ? r.stop() : r.start(host: host, room: room)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    Text(r.status).font(.headline)
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:12) {
                        Metric("Buffer", String(format:"%.1f ms",r.bufferMs))
                        Metric("Highest", String(format:"%.1f ms",r.maxBufferMs))
                        Metric("Received","\(r.received)")
                        Metric("Sequence gaps","\(r.sequenceGaps)")
                        Metric("Underruns","\(r.underruns)")
                        Metric("Recoveries","\(r.recoveries)")
                        Metric("Recovered",String(format:"%.1f ms",r.recoveredMs))
                        Metric("Audio rate","48000 Hz")
                    }
                    Text("Fixed pitch • stale audio is discarded, never played faster")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }.navigationTitle("Receiver")
        }
    }
}

private struct Metric: View {
    let title:String; let value:String
    init(_ t:String,_ v:String){title=t;value=v}
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).monospacedDigit()
        }.frame(maxWidth:.infinity,alignment:.leading).padding()
         .background(.thinMaterial,in:RoundedRectangle(cornerRadius:16))
    }
}
