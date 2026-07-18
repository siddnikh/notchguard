import AppKit
import Foundation
import QuartzCore

/// A short-lived, non-activating panel positioned beneath the camera housing.
/// It intentionally contains one message and one recovery action only.
public final class NotchOverlay: NSObject, @unchecked Sendable {
    public static let shared = NotchOverlay()

    private var panel: NSPanel?
    private var closeWorkItem: DispatchWorkItem?
    private var session: AgentSession?

    public func show(_ event: AgentEvent, session: AgentSession) {
        DispatchQueue.main.async { [weak self] in self?.present(event, session: session) }
    }

    public static func displayDuration(for kind: AgentEventKind) -> TimeInterval {
        switch kind {
        case .completed: return 6
        case .failed: return 10
        case .inputRequired, .approvalRequired: return 12
        }
    }

    private func present(_ event: AgentEvent, session: AgentSession) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        closeWorkItem?.cancel()
        panel?.orderOut(nil)
        self.session = session

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let size = NSSize(width: 382, height: 66)
        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.maxY - size.height - 22,
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
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = content(for: event, session: session, size: size)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        self.panel = panel

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 1
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }

        let workItem = DispatchWorkItem { [weak self] in self?.dismiss() }
        closeWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displayDuration(for: event.kind), execute: workItem)
    }

    private func content(for event: AgentEvent, session: AgentSession, size: NSSize) -> NSView {
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.backgroundColor = NSColor(calibratedWhite: 0.025, alpha: 0.96).cgColor
        effect.layer?.cornerRadius = 22
        effect.layer?.masksToBounds = true

        let status = NSView()
        status.wantsLayer = true
        status.layer?.backgroundColor = tint(for: event.kind).cgColor
        status.layer?.cornerRadius = 4
        status.translatesAutoresizingMaskIntoConstraints = false

        let titleText = session.agentName == "Notchguard" && event.kind == .completed
            ? "Notchguard is ready"
            : "\(session.agentName) \(event.actionTitle)"
        let title = NSTextField(labelWithString: titleText)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = NSColor(calibratedWhite: 0.97, alpha: 1)
        let detail = NSTextField(labelWithString: "\(session.projectName)  ·  \(event.summary)")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = NSColor(calibratedWhite: 0.68, alpha: 1)
        detail.lineBreakMode = .byTruncatingTail
        detail.maximumNumberOfLines = 1
        let labels = NSStackView(views: [title, detail])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false

        let button = NSButton(title: "Return", target: self, action: #selector(openTerminal))
        button.bezelStyle = .inline
        button.font = .systemFont(ofSize: 11, weight: .medium)
        button.contentTintColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        button.toolTip = "Return to the original Terminal tab"
        button.translatesAutoresizingMaskIntoConstraints = false

        effect.addSubview(status)
        effect.addSubview(labels)
        effect.addSubview(button)
        NSLayoutConstraint.activate([
            status.leadingAnchor.constraint(equalTo: effect.leadingAnchor, constant: 19),
            status.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            status.widthAnchor.constraint(equalToConstant: 8),
            status.heightAnchor.constraint(equalToConstant: 8),
            labels.leadingAnchor.constraint(equalTo: status.trailingAnchor, constant: 11),
            labels.centerYAnchor.constraint(equalTo: effect.centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: button.leadingAnchor, constant: -12),
            button.trailingAnchor.constraint(equalTo: effect.trailingAnchor, constant: -17),
            button.centerYAnchor.constraint(equalTo: effect.centerYAnchor)
        ])
        return effect
    }

    @objc private func openTerminal() {
        guard let session else { return }
        try? TerminalJumper.jump(to: session.workingDirectory, terminalTTY: session.terminalTTY)
        dismiss()
    }

    private func dismiss() {
        guard let panel else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.orderOut(nil)
        } else {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.12
                panel.animator().alphaValue = 0
            }, completionHandler: {
                panel.orderOut(nil)
            })
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
