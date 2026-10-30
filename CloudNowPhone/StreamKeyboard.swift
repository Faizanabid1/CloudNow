import SwiftUI
import UIKit

/// Invisible key-input view that raises the system keyboard and forwards every key to the
/// stream as it's typed. GFN doesn't report when a remote text field gains focus, so the
/// keyboard is opened by hand.
struct StreamKeyboard: UIViewRepresentable {
    @Binding var isActive: Bool
    let streamController: GFNStreamController

    func makeCoordinator() -> StreamTyping {
        StreamTyping(streamController: streamController)
    }

    func makeUIView(context: Context) -> KeyInputView {
        let view = KeyInputView()
        view.onInsert = { context.coordinator.type($0) }
        view.onDeleteBackward = { context.coordinator.press(.keyboardDeleteOrBackspace) }
        return view
    }

    func updateUIView(_ view: KeyInputView, context: Context) {
        view.onDismiss = { [streamController] in
            isActive = false
            // Hand hardware keyboard and Menu handling back to the video surface.
            streamController.videoView?.becomeFirstResponder()
        }
        if isActive, !view.isFirstResponder {
            view.becomeFirstResponder()
        } else if !isActive, view.isFirstResponder {
            view.resignFirstResponder()
        }
    }
}

final class KeyInputView: UIView, UIKeyInput {
    var onInsert: (String) -> Void = { _ in }
    var onDeleteBackward: () -> Void = {}
    var onDismiss: () -> Void = {}

    // Remote fields need the exact keys typed, not corrections or smart punctuation.
    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no
    var inlinePredictionType: UITextInlinePredictionType = .no

    override var canBecomeFirstResponder: Bool {
        true
    }

    /// Always claims text so Backspace keeps firing; the real text lives in the remote field.
    var hasText: Bool {
        true
    }

    func insertText(_ text: String) {
        onInsert(text)
    }

    func deleteBackward() {
        onDeleteBackward()
    }

    @discardableResult
    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            onDismiss()
        }
        return resigned
    }
}

/// Sends typed keys strictly in order. A text replay must finish before the next starts,
/// since starting one cancels any replay still in flight.
final class StreamTyping {
    private enum Item {
        case text(String)
        case key(UIKeyboardHIDUsage)
    }

    private weak var streamController: GFNStreamController?
    private var queue: [Item] = []
    private var isTyping = false

    init(streamController: GFNStreamController) {
        self.streamController = streamController
    }

    func type(_ text: String) {
        for character in text {
            if character.isNewline {
                queue.append(.key(.keyboardReturnOrEnter))
            } else if case let .text(pending)? = queue.last {
                queue[queue.count - 1] = .text(pending + String(character))
            } else {
                queue.append(.text(String(character)))
            }
        }
        sendNext()
    }

    func press(_ key: UIKeyboardHIDUsage) {
        queue.append(.key(key))
        sendNext()
    }

    private func sendNext() {
        guard !isTyping, let streamController else { return }
        while !queue.isEmpty {
            switch queue.removeFirst() {
            case let .key(key):
                streamController.pressKey(key)
            case let .text(text):
                isTyping = true
                streamController.typeText(text) { [weak self] _ in
                    self?.isTyping = false
                    self?.sendNext()
                }
                return
            }
        }
    }
}
