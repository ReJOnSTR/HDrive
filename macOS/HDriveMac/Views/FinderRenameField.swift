import SwiftUI
import AppKit

/// Native macOS Finder inline rename field with automatic text selection (excluding file extension),
/// return to commit, escape to cancel, tab to advance, and forbidden character filtering.
struct FinderRenameField: NSViewRepresentable {
    let initialText: String
    let isDirectory: Bool
    let textAlignment: NSTextAlignment
    let fontSize: CGFloat
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    let onTab: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField()
        textField.stringValue = initialText
        textField.isEditable = true
        textField.isSelectable = true
        textField.isBordered = false
        textField.drawsBackground = true
        textField.backgroundColor = NSColor.textBackgroundColor
        textField.layer?.cornerRadius = 3.5
        textField.layer?.borderWidth = 1.5
        textField.layer?.borderColor = NSColor.controlAccentColor.cgColor
        textField.wantsLayer = true
        textField.font = NSFont.systemFont(ofSize: fontSize)
        textField.alignment = textAlignment
        textField.focusRingType = .none
        textField.delegate = context.coordinator

        // Auto-focus and select base name without extension (macOS Finder native behavior)
        DispatchQueue.main.async {
            guard let window = textField.window else { return }
            window.makeFirstResponder(textField)
            if let editor = textField.currentEditor() {
                let text = textField.stringValue
                if !isDirectory, let dotIndex = text.lastIndex(of: "."), dotIndex != text.startIndex {
                    let length = text.distance(from: text.startIndex, to: dotIndex)
                    editor.selectedRange = NSRange(location: 0, length: length)
                } else {
                    editor.selectedRange = NSRange(location: 0, length: text.count)
                }
            }
        }

        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {}

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FinderRenameField
        var didComplete = false

        init(_ parent: FinderRenameField) {
            self.parent = parent
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                didComplete = true
                parent.onCommit(control.stringValue)
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                didComplete = true
                parent.onCancel()
                return true
            } else if commandSelector == #selector(NSResponder.insertTab(_:)) {
                didComplete = true
                parent.onCommit(control.stringValue)
                parent.onTab(false)
                return true
            } else if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                didComplete = true
                parent.onCommit(control.stringValue)
                parent.onTab(true)
                return true
            }
            return false
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            if !didComplete, let textField = obj.object as? NSTextField {
                didComplete = true
                parent.onCommit(textField.stringValue)
            }
        }

        func controlTextDidChange(_ obj: Notification) {
            if let textField = obj.object as? NSTextField {
                // Filter out invalid characters in macOS filenames (: and /)
                let filtered = textField.stringValue.replacingOccurrences(of: "/", with: "").replacingOccurrences(of: ":", with: "")
                if filtered != textField.stringValue {
                    let oldSelected = textField.currentEditor()?.selectedRange
                    textField.stringValue = filtered
                    if let old = oldSelected {
                        textField.currentEditor()?.selectedRange = old
                    }
                }
            }
        }
    }
}
