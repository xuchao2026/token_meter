import AppKit
import QuartzCore

final class RoundedVisualEffectView: NSVisualEffectView {
    var cornerRadius: CGFloat = 30 {
        didSet { updateRoundedMask() }
    }

    override func layout() {
        super.layout()
        updateRoundedMask()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateRoundedMask()
    }

    private func updateRoundedMask() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        layer?.cornerRadius = cornerRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        guard bounds.width > 1, bounds.height > 1 else { return }
        maskImage = Self.maskImage(size: bounds.size, radius: cornerRadius)
    }

    private static func maskImage(size: NSSize, radius: CGFloat) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setFill()
        NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: size),
            xRadius: radius,
            yRadius: radius
        ).fill()
        image.unlockFocus()
        return image
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let compactWindowSize = NSSize(width: 380, height: 291)
    private let detailWindowSize = NSSize(width: 470, height: 690)
    private var window: NSWindow!
    private var dashboardView: DashboardView!
    private var store: CodexUsageStore!
    private var statusItem: NSStatusItem!
    private var outsideClickMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        store = CodexUsageStore()
        dashboardView = DashboardView(store: store)
        dashboardView.onRefresh = { [weak self] in self?.store.refresh() }
        dashboardView.onHide = { [weak self] in self?.hideWindow() }
        dashboardView.onClose = { NSApp.terminate(nil) }
        dashboardView.onDetailModeChange = { [weak self] isShowingDetails in
            self?.resizeWindow(showingDetails: isShowingDetails)
        }

        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: compactWindowSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.title = "Token Meter"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true

        let containerView = RoundedVisualEffectView(frame: NSRect(origin: .zero, size: compactWindowSize))
        containerView.material = .popover
        containerView.blendingMode = .behindWindow
        containerView.state = .active
        containerView.autoresizingMask = [.width, .height]
        containerView.cornerRadius = 30

        dashboardView.frame = containerView.bounds
        dashboardView.autoresizingMask = [.width, .height]
        containerView.addSubview(dashboardView)
        window.contentView = containerView
        window.minSize = compactWindowSize
        window.maxSize = compactWindowSize
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.level = .floating

        configureStatusItem()

        store.onUpdate = { [weak self] state in
            self?.dashboardView.needsDisplay = true
            self?.updateStatusTitle(with: state)
        }
        store.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func toggleWindow() {
        if window.isVisible {
            hideWindow()
        } else {
            showWindow()
        }
    }

    private func showWindow() {
        dashboardView.showSummary()
        resizeWindow(showingDetails: false, animate: false)
        placeWindowBelowStatusIcon()
        window.orderFrontRegardless()
        startOutsideClickMonitor()
    }

    private func hideWindow() {
        window.orderOut(nil)
        stopOutsideClickMonitor()
    }

    private func resizeWindow(showingDetails: Bool, animate: Bool = true) {
        let size = showingDetails ? detailWindowSize : compactWindowSize
        let oldFrame = window.frame
        let cornerRadius: CGFloat = showingDetails ? 32 : 30
        (window.contentView as? RoundedVisualEffectView)?.cornerRadius = cornerRadius
        window.minSize = size
        window.maxSize = size

        let proposedOrigin = NSPoint(x: oldFrame.maxX - size.width, y: oldFrame.maxY - size.height)
        var frame = NSRect(origin: proposedOrigin, size: size)
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            frame.origin.x = min(max(visible.minX + 12, frame.origin.x), visible.maxX - size.width - 12)
            frame.origin.y = min(max(visible.minY + 12, frame.origin.y), visible.maxY - size.height - 12)
        }

        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                window.animator().setFrame(frame, display: true)
            } completionHandler: { [weak self] in
                self?.window.invalidateShadow()
                self?.window.contentView?.needsLayout = true
            }
        } else {
            window.setFrame(frame, display: true)
            window.invalidateShadow()
            window.contentView?.needsLayout = true
        }
    }

    private func startOutsideClickMonitor() {
        stopOutsideClickMonitor()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.window.isVisible else { return }
            let point = event.locationInWindow
            if self.window.frame.contains(point) || self.statusItemFrame()?.contains(point) == true {
                return
            }
            DispatchQueue.main.async {
                self.hideWindow()
            }
        }
    }

    private func stopOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    @objc private func refreshUsage() {
        store.refresh()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func placeWindowBelowStatusIcon() {
        guard let screen = NSScreen.main else {
            window.center()
            return
        }

        let iconFrame = statusItemFrame()

        let visibleFrame = screen.visibleFrame
        let size = window.frame.size
        let proposedX = (iconFrame?.midX ?? visibleFrame.maxX) - size.width + 26
        let x = min(max(visibleFrame.minX + 12, proposedX), visibleFrame.maxX - size.width - 12)
        let y = min(
            visibleFrame.maxY - size.height - 12,
            max(visibleFrame.minY + 12, (iconFrame?.minY ?? visibleFrame.maxY) - size.height - 10)
        )
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func statusItemFrame() -> NSRect? {
        guard let button = statusItem.button,
              let buttonWindow = button.window else {
            return nil
        }
        return buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = nil
        button.attributedTitle = statusBarTitle("--%", color: .systemGray)
        button.target = self
        button.action = #selector(toggleWindow)
        button.toolTip = "Codex Token 额度 · 5小时余 --%"
    }

    private func updateStatusTitle(with state: CodexUsageSnapshot) {
        let remaining = statusPercent(for: state.primaryWindow.remainingPercent)
        statusItem.button?.attributedTitle = statusBarTitle(
            remaining,
            color: statusColor(for: state.primaryWindow.remainingPercent)
        )
        statusItem.button?.toolTip = "Codex Token 额度 · 5小时余 \(remaining) · 今日 \(Formatters.tokens(state.today.totalTokens))"
    }

    private func statusColor(for remaining: Double?) -> NSColor {
        guard let remaining else { return .systemGray }
        if remaining < 10 { return .systemRed }
        if remaining < 20 { return .systemYellow }
        return .systemGreen
    }

    private func statusPercent(for remaining: Double?) -> String {
        guard let remaining else { return "--%" }
        return "\(Int(round(max(0, min(remaining, 100)))))%"
    }

    private func statusBarTitle(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .heavy),
                .foregroundColor: color
            ]
        )
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
