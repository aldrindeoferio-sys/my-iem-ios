import SwiftUI

struct ContentView: View {
 @EnvironmentObject var r:AudioReceiver
 @State private var host="192.168.0.193"
 @State private var room="stage"
 var body:some View {
  NavigationStack {
   ScrollView {
    VStack(spacing:16) {
     Text("MY IEM").font(.largeTitle.bold())
     Text("Native Hybrid Receiver • v0.2").foregroundStyle(.secondary)
     TextField("Sender IP",text:$host).textFieldStyle(.roundedBorder).keyboardType(.numbersAndPunctuation)
     TextField("Room",text:$room).textFieldStyle(.roundedBorder)
     Button(r.running ? "STOP":"START"){r.running ? r.stop():r.start(host:host,room:room)}
      .buttonStyle(.borderedProminent).controlSize(.large)
     Text(r.status).font(.headline)
     LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:10){
      Metric("Live buffer",String(format:"%.1f ms",r.bufferMs))
      Metric("Highest",String(format:"%.1f ms",r.maxBufferMs))
      Metric("Adaptive target",String(format:"%.1f ms",r.targetMs))
      Metric("Network jitter",String(format:"%.1f ms",r.jitterMs))
      Metric("Packets","\(r.received)")
      Metric("Missing","\(r.sequenceGaps)")
      Metric("Late","\(r.latePackets)")
      Metric("Reordered","\(r.reordered)")
      Metric("Underruns","\(r.underruns)")
      Metric("Recoveries","\(r.recoveries)")
     }
     Text("48 kHz • UDP datagrams • fixed pitch • adaptive jitter deadline • stale packets rejected")
      .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
    }.padding()
   }.navigationTitle("Receiver")
  }
 }
}
private struct Metric:View {
 let t:String,v:String
 init(_ t:String,_ v:String){self.t=t;self.v=v}
 var body:some View {VStack(alignment:.leading){Text(t).foregroundStyle(.secondary);Text(v).font(.title3.bold()).monospacedDigit()}.frame(maxWidth:.infinity,alignment:.leading).padding().background(.thinMaterial,in:RoundedRectangle(cornerRadius:14))}
}
