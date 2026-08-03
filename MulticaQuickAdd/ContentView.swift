import SwiftUI

struct ContentView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(AppMetadata.name)
        .font(.title.bold())

      Text("Issue creation will live here.")
        .foregroundStyle(.secondary)
    }
    .frame(width: 420, alignment: .leading)
    .padding(32)
  }
}

#Preview {
  ContentView()
}
