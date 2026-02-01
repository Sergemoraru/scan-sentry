import SwiftUI
import UIKit

struct PasteSheet: View {
    @Binding var pasteText: String
    var onUse: ((String) -> Void)?
    var onClose: (() -> Void)?

    // Default initializer for call sites that use PasteSheet() with no parameters
    init() {
        self._pasteText = .constant("")
        self.onUse = nil
        self.onClose = nil
    }

    // Common initializer for call sites using pasteText label
    init(pasteText: Binding<String>, onUse: ((String) -> Void)? = nil, onClose: (() -> Void)? = nil) {
        self._pasteText = pasteText
        self.onUse = onUse
        self.onClose = onClose
    }

    // Alternate initializer for call sites using text label
    init(text: Binding<String>, onUse: ((String) -> Void)? = nil, onClose: (() -> Void)? = nil) {
        self._pasteText = text
        self.onUse = onUse
        self.onClose = onClose
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Paste a QR payload") {
                    TextEditor(text: $pasteText)
                        .frame(minHeight: 160)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Button("Use This") {
                    if let onUse { onUse(pasteText) } else { UIPasteboard.general.string = pasteText }
                    onClose?()
                }
            }
            .navigationTitle("Paste")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onClose?() }
                }
            }
        }
    }
}
