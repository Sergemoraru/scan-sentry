import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Reuse the existing HowToUseView content
                HowToUseView()
                
                // Fixed bottom button
                VStack {
                    Button {
                        isPresented = false
                    } label: {
                        Text("Start Scanning")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }
                .padding()
                .background(.regularMaterial)
            }
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
