import SwiftUI

struct MenuBarView: View {
    let snapshot: MemorySnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MemWatch")
                .font(.headline)

            Text("RAM: \(percentUsed)%")
            Text("Swap: \(bytes(snapshot.swapUsedBytes))")
            Text("Pressure: \(snapshot.pressure.rawValue)")
        }
        .padding()
    }

    private var percentUsed: Int {
        guard snapshot.totalBytes > 0 else { return 0 }
        return Int(Double(snapshot.usedBytes) / Double(snapshot.totalBytes) * 100)
    }

    private func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .memory)
    }
}
