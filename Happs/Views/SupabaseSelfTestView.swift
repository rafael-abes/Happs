import SwiftUI

/// F0 check. Temporary: reach it from a DEBUG-only row, then remove once it passes.
struct SupabaseSelfTestView: View {
    @State private var output = "Tap Run test while signed in."
    @State private var isRunning = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Button {
                    isRunning = true
                    Task {
                        output = await SupabaseStorageService.shared.selfTest()
                        isRunning = false
                    }
                } label: {
                    Text(isRunning ? "Running..." : "Run test")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRunning)

                Text(output)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(20)
        }
        .navigationTitle("Supabase test")
        .navigationBarTitleDisplayMode(.inline)
    }
}
