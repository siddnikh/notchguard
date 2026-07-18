import AppKit
import Foundation

/// A short-lived, non-activating panel positioned beneath the camera housing.
/// It intentionally contains one message and one recovery action only.
public final class NotchOverlay: NSObject, @unchecked Sendable {
    public static let shared = NotchOverlay()

    private var panel: NSPanel?
    private var closeWorkItem: DispatchWorkItem?

    public func show(_ event: AgentEvent) {
        DispatchQueue.main.async { [weak self] in self?.present(event) }
    }

    private func present(_ event: AgentEvent) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        closeWorkItem?.cancel()
        panel?.orderOut(nil)

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = NSSize(width: 440, height: 78)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - 28,
            width: size.width,
            height: size.height
        )
        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentView = content(for: event, size: size)
        panel.orderFrontRegardless()
        self.panel = panel

        let workItem = DispatchWorkItem { [weak panel] in panel?.orderOut(nil) }
        closeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 12, execute: workItem)
    }

    private func content(for event: AgentEvent, size: NSSize) -> NSView {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .hudWindow
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 24
        effect.layer?.masksToBounds = true

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol(for: event.kind), accessibilityDescription: event.title)
        icon.contentTintColor = tint(for: event.kind)
        icon.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: event.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let detail = NSTextField(labelWithString: event.summary)
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        detail.lineBreakMode = .byTruncatingTail
        detail.maximumNumberOfLines = 1
        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: "Open Terminal", target: self, action: #selector(openTerminal))
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(icon)
        effect.addSubview(labels)
        effect.addSubview(button)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 22),
            icon.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
            labels.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 12),
            labels.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),
            button.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -20),
            button.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
        ])
        return effect
    }

    @objc private func openTerminal() {
        try? TerminalJumper.jump(to: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
        panel?.orderOut(nil)
    }

    private func symbol(for kind: AgentEventKind) -> String {
        switch kind {
        case .inputRequired: return "text.cursor"
        case .approvalRequired: return "hand.raised.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private func tint(for kind: AgentEventKind) -> NSColor {
        switch kind {
        case .inputRequired: return .systemBlue
        case .approvalRequired: return .systemOrange
        case .completed: return .systemGreen
        case .failed: return .systemRed
        }
    }
}

