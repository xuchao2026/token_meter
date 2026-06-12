import AppKit
import QuartzCore

final class DashboardView: NSView {
    var onRefresh: (() -> Void)?
    var onHide: (() -> Void)?
    var onClose: (() -> Void)?
    var onPinToggle: ((Bool) -> Void)?
    var onDetailModeChange: ((Bool) -> Void)?
    var isPinned = false {
        didSet { needsDisplay = true }
    }

    private let store: CodexUsageStore
    private var isShowingDetails = false

    private var refreshButtonRect = CGRect.zero
    private var pinButtonRect = CGRect.zero
    private var hideButtonRect = CGRect.zero
    private var closeButtonRect = CGRect.zero
    private var detailButtonRect = CGRect.zero
    private let compactDesignSize = CGSize(width: 618, height: 430)
    private let detailDesignSize = CGSize(width: 620, height: 900)
    private var designSize: CGSize {
        isShowingDetails ? detailDesignSize : compactDesignSize
    }
    private var animationPhase: CGFloat = 0
    private var animationTimer: Timer?
    private weak var snapshotTransitionLayer: CALayer?
    private weak var incomingTransitionLayer: CALayer?
    private var hidesPageDuringTransition = false
    private var detailRingProgress: CGFloat = 1
    private let detailRingDuration: CGFloat = 1.35
    private var trendDrawProgress: CGFloat = 1
    private let trendDrawDuration: CGFloat = 1.7
    private var detailPrimaryPercentStart: CGFloat = 0
    private var detailPrimaryPercentTarget: CGFloat = 0
    private var detailSecondaryPercentStart: CGFloat = 0
    private var detailSecondaryPercentTarget: CGFloat = 0
    private var animatedHistorySignature = ""
    private var trackingArea: NSTrackingArea?
    private var trendHoverRegions: [TrendHoverRegion] = []
    private var hoveredTrendIndex: Int?

    private let panelFill = NSColor(calibratedRed: 0.89, green: 0.90, blue: 0.88, alpha: 0.26)
    private let glassFill = NSColor(calibratedRed: 1.0, green: 0.96, blue: 0.88, alpha: 0.34)
    private let hotGlassFill = NSColor(calibratedRed: 1.0, green: 0.70, blue: 0.72, alpha: 0.24)
    private let borderColor = NSColor(calibratedRed: 0.46, green: 0.50, blue: 0.54, alpha: 0.24)
    private let hotBorderColor = NSColor(calibratedRed: 0.86, green: 0.24, blue: 0.30, alpha: 0.54)
    private let textColor = NSColor(calibratedRed: 0.09, green: 0.10, blue: 0.12, alpha: 1)
    private let mutedTextColor = NSColor(calibratedRed: 0.33, green: 0.35, blue: 0.38, alpha: 1)
    private let red = NSColor(calibratedRed: 0.95, green: 0.24, blue: 0.29, alpha: 1)
    private let yellow = NSColor(calibratedRed: 0.90, green: 0.63, blue: 0.20, alpha: 1)
    private let green = NSColor(calibratedRed: 0.15, green: 0.72, blue: 0.38, alpha: 1)
    private let sevenDayStatColor = NSColor(calibratedRed: 0.00, green: 0.48, blue: 0.78, alpha: 1)
    init(store: CodexUsageStore) {
        self.store = store
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    deinit {
        animationTimer?.invalidate()
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            animationTimer?.invalidate()
            animationTimer = nil
        } else {
            window?.acceptsMouseMovedEvents = true
            startAnimation()
        }
    }

    override func layout() {
        super.layout()
        updateTransitionLayerFrames()
    }

    override func updateTrackingAreas() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let nextArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .inVisibleRect, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(nextArea)
        trackingArea = nextArea
        super.updateTrackingAreas()
    }

    override func mouseDown(with event: NSEvent) {
        let point = designPoint(from: convert(event.locationInWindow, from: nil))

        if refreshButtonRect.contains(point) {
            onRefresh?()
            return
        }
        if pinButtonRect.contains(point) {
            isPinned.toggle()
            onPinToggle?(isPinned)
            return
        }
        if hideButtonRect.contains(point) {
            onHide?()
            return
        }
        if closeButtonRect.contains(point) {
            onClose?()
            return
        }
        if detailButtonRect.contains(point) {
            setShowingDetails(!isShowingDetails, animated: true)
            return
        }

        super.mouseDown(with: event)
    }

    override func mouseMoved(with event: NSEvent) {
        updateTrendHover(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseExited(with event: NSEvent) {
        clearTrendHover()
    }

    func showSummary() {
        clearTrendHover()
        isShowingDetails = false
        snapshotTransitionLayer?.removeFromSuperlayer()
        snapshotTransitionLayer = nil
        incomingTransitionLayer?.removeFromSuperlayer()
        incomingTransitionLayer = nil
        hidesPageDuringTransition = false
        detailRingProgress = 1
        trendDrawProgress = 1
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        refreshButtonRect = .zero
        pinButtonRect = .zero
        hideButtonRect = .zero
        closeButtonRect = .zero
        detailButtonRect = .zero
        if !isShowingDetails {
            trendHoverRegions = []
        }

        let transform = designTransform()
        NSGraphicsContext.saveGraphicsState()
        let affine = NSAffineTransform()
        affine.translateX(by: transform.origin.x, yBy: transform.origin.y)
        affine.scaleX(by: transform.scale, yBy: transform.scale)
        affine.concat()

        let rootInset: CGFloat = 0
        let root = CGRect(origin: .zero, size: designSize).insetBy(dx: rootInset, dy: rootInset)
        let state = store.snapshot
        if isShowingDetails {
            syncDetailAnimations(with: state, restart: false)
        }

        if !hidesPageDuringTransition {
            drawPage(in: root, state: state)
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func setShowingDetails(_ showingDetails: Bool, animated: Bool) {
        guard isShowingDetails != showingDetails else { return }
        let outgoingSnapshot = animated
            ? makePageSnapshot(showingDetails: isShowingDetails, state: store.snapshot)
            : nil
        isShowingDetails = showingDetails
        clearTrendHover()
        if showingDetails {
            syncDetailAnimations(with: store.snapshot, restart: true)
        } else {
            detailRingProgress = 1
            trendDrawProgress = 1
        }
        let incomingSnapshot = animated && !showingDetails
            ? makePageSnapshot(showingDetails: showingDetails, state: store.snapshot)
            : nil
        if showingDetails, let outgoingSnapshot {
            startOutgoingFadeTransition(from: outgoingSnapshot, openingDetails: true)
        } else if let outgoingSnapshot, let incomingSnapshot {
            hidesPageDuringTransition = true
            startControlCenterTransition(
                from: outgoingSnapshot,
                to: incomingSnapshot,
                openingDetails: showingDetails
            )
        }
        needsDisplay = true
        onDetailModeChange?(showingDetails)
    }

    private func drawPage(in root: CGRect, state: CodexUsageSnapshot) {
        NSGraphicsContext.saveGraphicsState()
        drawChrome(in: root)
        drawHeader(in: root, state: state)
        drawContent(in: root, state: state, showingDetails: isShowingDetails)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawContent(in root: CGRect, state: CodexUsageSnapshot, showingDetails: Bool) {
        if showingDetails {
            drawDetails(in: root, state: state)
        } else {
            drawQuotaContent(in: root, state: state)
        }
    }

    private func makePageSnapshot(showingDetails: Bool, state: CodexUsageSnapshot) -> NSImage {
        let size = showingDetails ? detailDesignSize : compactDesignSize
        let image = NSImage(size: size)
        let root = CGRect(origin: .zero, size: size)

        let savedRefreshButtonRect = refreshButtonRect
        let savedPinButtonRect = pinButtonRect
        let savedHideButtonRect = hideButtonRect
        let savedCloseButtonRect = closeButtonRect
        let savedDetailButtonRect = detailButtonRect
        let savedTrendHoverRegions = trendHoverRegions

        image.lockFocusFlipped(true)
        NSGraphicsContext.current?.imageInterpolation = .high
        NSColor.clear.setFill()
        root.fill()
        drawChrome(in: root)
        drawHeader(in: root, state: state)
        drawContent(in: root, state: state, showingDetails: showingDetails)
        image.unlockFocus()

        refreshButtonRect = savedRefreshButtonRect
        pinButtonRect = savedPinButtonRect
        hideButtonRect = savedHideButtonRect
        closeButtonRect = savedCloseButtonRect
        detailButtonRect = savedDetailButtonRect
        trendHoverRegions = savedTrendHoverRegions

        return image
    }

    private func updateTransitionLayerFrames() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if let snapshotTransitionLayer {
            snapshotTransitionLayer.bounds = CGRect(origin: .zero, size: bounds.size)
            snapshotTransitionLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        }
        if let incomingTransitionLayer {
            incomingTransitionLayer.bounds = CGRect(origin: .zero, size: bounds.size)
            incomingTransitionLayer.position = CGPoint(x: bounds.maxX, y: bounds.maxY)
        }
        CATransaction.commit()
    }

    private func startControlCenterTransition(from outgoingImage: NSImage, to incomingImage: NSImage, openingDetails: Bool) {
        guard let hostLayer = layer,
              let outgoingCGImage = outgoingImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let incomingCGImage = incomingImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            hidesPageDuringTransition = false
            needsDisplay = true
            return
        }

        snapshotTransitionLayer?.removeFromSuperlayer()
        incomingTransitionLayer?.removeFromSuperlayer()

        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let outgoingLayer = CALayer()
        outgoingLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        outgoingLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        outgoingLayer.contents = outgoingCGImage
        outgoingLayer.contentsGravity = .resizeAspect
        outgoingLayer.contentsScale = backingScale
        outgoingLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        outgoingLayer.allowsEdgeAntialiasing = true
        outgoingLayer.masksToBounds = true
        outgoingLayer.cornerRadius = openingDetails ? 30 : 32
        outgoingLayer.cornerCurve = .continuous
        hostLayer.addSublayer(outgoingLayer)
        snapshotTransitionLayer = outgoingLayer

        let incomingLayer = CALayer()
        incomingLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        incomingLayer.position = CGPoint(x: bounds.maxX, y: bounds.maxY)
        incomingLayer.contents = incomingCGImage
        incomingLayer.contentsGravity = .resizeAspect
        incomingLayer.contentsScale = backingScale
        incomingLayer.anchorPoint = CGPoint(x: 1, y: 1)
        incomingLayer.allowsEdgeAntialiasing = true
        incomingLayer.masksToBounds = true
        incomingLayer.cornerRadius = openingDetails ? 32 : 30
        incomingLayer.cornerCurve = .continuous
        incomingLayer.opacity = 0
        incomingLayer.transform = CATransform3DMakeScale(openingDetails ? 0.72 : 1.04, openingDetails ? 0.72 : 1.04, 1)
        hostLayer.addSublayer(incomingLayer)
        incomingTransitionLayer = incomingLayer

        let timing = CAMediaTimingFunction(controlPoints: 0.18, 0.88, 0.20, 1.0)
        let duration = CFTimeInterval(openingDetails ? 0.42 : 0.34)
        let outgoingDuration = CFTimeInterval(openingDetails ? 0.09 : 0.08)

        let outgoingFade = CABasicAnimation(keyPath: "opacity")
        outgoingFade.fromValue = NSNumber(value: 1)
        outgoingFade.toValue = NSNumber(value: 0)

        let outgoingScale = CABasicAnimation(keyPath: "transform")
        outgoingScale.fromValue = NSValue(caTransform3D: CATransform3DIdentity)
        outgoingScale.toValue = NSValue(caTransform3D: CATransform3DMakeScale(openingDetails ? 0.992 : 1.01, openingDetails ? 0.992 : 1.01, 1))

        let outgoingMove = CABasicAnimation(keyPath: "position")
        outgoingMove.fromValue = NSValue(point: outgoingLayer.position)
        outgoingMove.toValue = NSValue(
            point: CGPoint(
                x: outgoingLayer.position.x,
                y: outgoingLayer.position.y + (openingDetails ? -3 : 4)
            )
        )

        let outgoingGroup = CAAnimationGroup()
        outgoingGroup.animations = [outgoingFade, outgoingScale, outgoingMove]
        outgoingGroup.duration = outgoingDuration
        outgoingGroup.timingFunction = CAMediaTimingFunction(name: .easeOut)
        outgoingGroup.fillMode = .forwards
        outgoingGroup.isRemovedOnCompletion = false

        let incomingFade = CABasicAnimation(keyPath: "opacity")
        incomingFade.fromValue = NSNumber(value: 0)
        incomingFade.toValue = NSNumber(value: 1)
        incomingFade.duration = CFTimeInterval(openingDetails ? 0.16 : 0.12)
        incomingFade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        incomingFade.fillMode = .forwards
        incomingFade.isRemovedOnCompletion = false

        let incomingScale = CABasicAnimation(keyPath: "transform")
        incomingScale.fromValue = NSValue(caTransform3D: incomingLayer.transform)
        incomingScale.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        incomingScale.duration = duration
        incomingScale.timingFunction = timing
        incomingScale.fillMode = .forwards
        incomingScale.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak outgoingLayer, weak incomingLayer] in
            guard let self else { return }
            outgoingLayer?.removeFromSuperlayer()
            incomingLayer?.removeFromSuperlayer()
            if self.snapshotTransitionLayer === outgoingLayer {
                self.snapshotTransitionLayer = nil
            }
            if self.incomingTransitionLayer === incomingLayer {
                self.incomingTransitionLayer = nil
            }
            self.hidesPageDuringTransition = false
            self.needsDisplay = true
        }
        outgoingLayer.opacity = 0
        outgoingLayer.transform = CATransform3DMakeScale(openingDetails ? 0.992 : 1.01, openingDetails ? 0.992 : 1.01, 1)
        outgoingLayer.position = CGPoint(
            x: outgoingLayer.position.x,
            y: outgoingLayer.position.y + (openingDetails ? -3 : 4)
        )
        incomingLayer.opacity = 1
        incomingLayer.transform = CATransform3DIdentity
        outgoingLayer.add(outgoingGroup, forKey: "control-center-outgoing")
        incomingLayer.add(incomingFade, forKey: "control-center-incoming-fade")
        incomingLayer.add(incomingScale, forKey: "control-center-incoming-scale")
        CATransaction.commit()
    }

    private func startOutgoingFadeTransition(from image: NSImage, openingDetails: Bool) {
        guard let hostLayer = layer,
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            needsDisplay = true
            return
        }

        snapshotTransitionLayer?.removeFromSuperlayer()
        incomingTransitionLayer?.removeFromSuperlayer()
        incomingTransitionLayer = nil
        hidesPageDuringTransition = false

        let backingScale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let outgoingLayer = CALayer()
        outgoingLayer.bounds = CGRect(origin: .zero, size: bounds.size)
        outgoingLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
        outgoingLayer.contents = cgImage
        outgoingLayer.contentsGravity = .resizeAspect
        outgoingLayer.contentsScale = backingScale
        outgoingLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        outgoingLayer.allowsEdgeAntialiasing = true
        outgoingLayer.masksToBounds = true
        outgoingLayer.cornerRadius = openingDetails ? 30 : 32
        outgoingLayer.cornerCurve = .continuous
        hostLayer.addSublayer(outgoingLayer)
        snapshotTransitionLayer = outgoingLayer

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = NSNumber(value: 1)
        fade.toValue = NSNumber(value: 0)
        fade.duration = 0.07
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        fade.fillMode = .forwards
        fade.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self, weak outgoingLayer] in
            outgoingLayer?.removeFromSuperlayer()
            if self?.snapshotTransitionLayer === outgoingLayer {
                self?.snapshotTransitionLayer = nil
            }
            self?.needsDisplay = true
        }
        outgoingLayer.opacity = 0
        outgoingLayer.add(fade, forKey: "quick-outgoing-fade")
        CATransaction.commit()
    }

    private func syncDetailAnimations(with state: CodexUsageSnapshot, restart: Bool) {
        let primaryTarget = normalizedPercent(state.primaryWindow.remainingPercent)
        let secondaryTarget = normalizedPercent(state.secondaryWindow.remainingPercent)
        let historySignature = trendSignature(for: state.history)

        if restart {
            detailPrimaryPercentStart = 0
            detailPrimaryPercentTarget = primaryTarget
            detailSecondaryPercentStart = 0
            detailSecondaryPercentTarget = secondaryTarget
            detailRingProgress = 0
            animatedHistorySignature = historySignature
            trendDrawProgress = 0
            return
        }

        if abs(primaryTarget - detailPrimaryPercentTarget) > 0.001 ||
            abs(secondaryTarget - detailSecondaryPercentTarget) > 0.001 {
            detailPrimaryPercentStart = animatedPercent(
                from: detailPrimaryPercentStart,
                to: detailPrimaryPercentTarget,
                progress: detailRingProgress
            )
            detailSecondaryPercentStart = animatedPercent(
                from: detailSecondaryPercentStart,
                to: detailSecondaryPercentTarget,
                progress: detailRingProgress
            )
            detailPrimaryPercentTarget = primaryTarget
            detailSecondaryPercentTarget = secondaryTarget
            detailRingProgress = 0
        }

        if historySignature != animatedHistorySignature {
            animatedHistorySignature = historySignature
            trendDrawProgress = 0
        }
    }

    private func animatedPrimaryPercent() -> CGFloat {
        animatedPercent(
            from: detailPrimaryPercentStart,
            to: detailPrimaryPercentTarget,
            progress: detailRingProgress
        )
    }

    private func animatedSecondaryPercent() -> CGFloat {
        animatedPercent(
            from: detailSecondaryPercentStart,
            to: detailSecondaryPercentTarget,
            progress: detailRingProgress
        )
    }

    private func animatedPercent(from start: CGFloat, to target: CGFloat, progress: CGFloat) -> CGFloat {
        start + (target - start) * smoothStep(progress)
    }

    private func easedTrendDrawProgress() -> CGFloat {
        smoothStep(trendDrawProgress)
    }

    private func smoothStep(_ value: CGFloat) -> CGFloat {
        let progress = max(0, min(value, 1))
        return progress * progress * (3 - 2 * progress)
    }

    private func normalizedPercent(_ percent: Double?) -> CGFloat {
        CGFloat(max(0, min((percent ?? 0) / 100, 1)))
    }

    private func percentText(_ percent: CGFloat) -> String {
        "\(Int(round(max(0, min(percent, 1)) * 100)))%"
    }

    private func trendSignature(for history: [DailyUsagePoint]) -> String {
        history.map { "\($0.dayID):\($0.totals.totalTokens)" }.joined(separator: "|")
    }

    private func updateTrendHover(at point: CGPoint) {
        guard isShowingDetails else {
            clearTrendHover()
            return
        }

        let designPoint = designPoint(from: point)
        let nextIndex = trendHoverRegions.first { $0.rect.contains(designPoint) }?.index
        if nextIndex != hoveredTrendIndex {
            hoveredTrendIndex = nextIndex
            needsDisplay = true
        }
    }

    private func clearTrendHover() {
        guard hoveredTrendIndex != nil else { return }
        hoveredTrendIndex = nil
        needsDisplay = true
    }

    private func drawChrome(in rect: CGRect) {
        let radius: CGFloat = 48
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        panelFill.setFill()
        path.fill()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let backdrop = NSGradient(colors: [
            NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.76, alpha: 0.14),
            NSColor(calibratedRed: 1.0, green: 0.91, blue: 0.57, alpha: 0.12),
            NSColor(calibratedRed: 0.28, green: 0.55, blue: 1.0, alpha: 0.14)
        ])
        backdrop?.draw(in: rect, angle: -78)

        NSColor.white.withAlphaComponent(0.08).setFill()
        rect.fill()
        NSColor.white.withAlphaComponent(0.20).setStroke()
        NSBezierPath(roundedRect: rect.insetBy(dx: 10, dy: 10), xRadius: radius - 10, yRadius: radius - 10).stroke()
        NSGraphicsContext.restoreGraphicsState()

        let inner = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: radius - 2, yRadius: radius - 2)
        borderColor.setStroke()
        inner.lineWidth = 1.4
        inner.stroke()
    }

    private func drawHeader(in root: CGRect, state: CodexUsageSnapshot) {
        let status = overallQuotaStatus(for: state)
        let outerInset: CGFloat = 24
        let leadingHeaderOffset: CGFloat = 12
        let headerLeadingX = root.minX + outerInset + leadingHeaderOffset
        let titleX = headerLeadingX + 50
        let titleY = root.minY + outerInset
        let statusY = titleY + 10
        let buttonY = root.minY + outerInset
        let dotOuter = CGRect(x: headerLeadingX, y: statusY, width: 34, height: 34)
        drawStatusLight(in: dotOuter, color: status.color, animated: hasQuotaData(state))

        drawFittedText(
            "Codex",
            in: CGRect(x: titleX, y: titleY, width: 250, height: 42),
            font: .systemFont(ofSize: 32, weight: .heavy),
            color: textColor,
            alignment: .left
        )
        drawFittedText(
            (state.planType ?? "FREE").uppercased(),
            in: CGRect(x: titleX + 2, y: titleY + 42, width: 230, height: 28),
            font: .systemFont(ofSize: 20, weight: .heavy),
            color: mutedTextColor,
            alignment: .left
        )

        let buttonSize: CGFloat = 52
        let gap: CGFloat = 14
        closeButtonRect = CGRect(x: root.maxX - outerInset - buttonSize, y: buttonY, width: buttonSize, height: buttonSize)
        hideButtonRect = CGRect(x: closeButtonRect.minX - gap - buttonSize, y: closeButtonRect.minY, width: buttonSize, height: buttonSize)
        refreshButtonRect = CGRect(x: hideButtonRect.minX - gap - buttonSize, y: closeButtonRect.minY, width: buttonSize, height: buttonSize)

        if isShowingDetails {
            pinButtonRect = CGRect(x: refreshButtonRect.minX - gap - buttonSize, y: closeButtonRect.minY, width: buttonSize, height: buttonSize)
            detailButtonRect = CGRect(x: pinButtonRect.minX - gap - 88, y: closeButtonRect.minY, width: 88, height: buttonSize)
            drawDetailButton(title: "返回", in: detailButtonRect)
        } else {
            pinButtonRect = CGRect(x: refreshButtonRect.minX - gap - buttonSize, y: closeButtonRect.minY, width: buttonSize, height: buttonSize)
        }
        drawIconButton(in: refreshButtonRect, kind: .refresh, spinning: store.isRefreshing)
        drawIconButton(in: pinButtonRect, kind: .pin, spinning: false, active: isPinned)
        drawIconButton(in: hideButtonRect, kind: .minus, spinning: false)
        drawIconButton(in: closeButtonRect, kind: .close, spinning: false)
    }

    private func drawQuotaContent(in root: CGRect, state: CodexUsageSnapshot) {
        let status = quotaStatus(for: state.primaryWindow)
        let secondaryStatus = quotaStatus(for: state.secondaryWindow)
        let compactInset: CGFloat = 24
        let meterRect = CGRect(x: root.minX + compactInset, y: root.minY + 166, width: 204, height: 204)
        drawMeter(
            in: meterRect,
            remainingPercent: state.primaryWindow.remainingPercent,
            color: status.color,
            animated: state.primaryWindow.remainingPercent != nil
        )

        let cardWidth: CGFloat = 322
        let cardX = root.maxX - compactInset - cardWidth
        let cardHeight: CGFloat = 106
        let sectionGap: CGFloat = 16
        let primaryCardRect = CGRect(x: cardX, y: root.minY + 112, width: cardWidth, height: cardHeight)
        let secondaryCardRect = CGRect(
            x: cardX,
            y: primaryCardRect.maxY + sectionGap,
            width: cardWidth,
            height: cardHeight
        )

        drawInfoCard(
            title: "5小时窗口",
            resetTime: resetClock(state.primaryWindow.resetsAt, style: .hourMinute),
            percent: Formatters.remainingPercent(state.primaryWindow),
            remaining: resetDescription(state.primaryWindow.resetsAt),
            in: primaryCardRect,
            style: .shortDuration,
            tint: state.primaryWindow.remainingPercent == nil ? nil : status.color
        )
        drawInfoCard(
            title: "7天窗口",
            resetTime: resetClock(state.secondaryWindow.resetsAt, style: .monthDayHourMinute),
            percent: Formatters.remainingPercent(state.secondaryWindow),
            remaining: resetDescription(state.secondaryWindow.resetsAt),
            in: secondaryCardRect,
            style: .longDuration,
            tint: state.secondaryWindow.remainingPercent == nil ? nil : secondaryStatus.color
        )
        detailButtonRect = CGRect(x: cardX, y: secondaryCardRect.maxY + sectionGap, width: cardWidth, height: 56)
        drawDetailButton(title: "详情", in: detailButtonRect)
    }

    private func drawDetails(in root: CGRect, state: CodexUsageSnapshot) {
        let primaryStatus = quotaStatus(for: state.primaryWindow)
        let secondaryStatus = quotaStatus(for: state.secondaryWindow)
        let detailInset: CGFloat = 16
        let sectionGap: CGFloat = 16
        let heroRect = CGRect(x: root.minX + detailInset, y: root.minY + 108, width: root.width - detailInset * 2, height: 250)
        drawDetailHero(in: heroRect, state: state)

        let cardGap: CGFloat = 12
        let cardY = heroRect.maxY + sectionGap
        let cardW = (root.width - detailInset * 2 - cardGap * 2) / 3
        let cardHeight: CGFloat = 116
        drawTokenCard(
            title: "5 小时余额",
            value: Formatters.remainingPercent(state.primaryWindow),
            subtitle: "已用 \(Formatters.usedPercent(state.primaryWindow.usedPercent))",
            accent: primaryStatus.color,
            in: CGRect(x: root.minX + detailInset, y: cardY, width: cardW, height: cardHeight)
        )
        drawTokenCard(
            title: "7 天余额",
            value: Formatters.remainingPercent(state.secondaryWindow),
            subtitle: "已用 \(Formatters.usedPercent(state.secondaryWindow.usedPercent))",
            accent: secondaryStatus.color,
            in: CGRect(x: root.minX + detailInset + cardW + cardGap, y: cardY, width: cardW, height: cardHeight)
        )
        drawTokenCard(
            title: "今日 Token",
            value: Formatters.tokens(state.today.totalTokens),
            subtitle: "本月 \(Formatters.tokens(state.month.totalTokens))",
            accent: textColor,
            in: CGRect(x: root.minX + detailInset + (cardW + cardGap) * 2, y: cardY, width: cardW, height: cardHeight)
        )

        let consumptionRect = CGRect(
            x: root.minX + detailInset,
            y: cardY + cardHeight + sectionGap,
            width: root.width - detailInset * 2,
            height: 160
        )
        drawConsumptionBoard(in: consumptionRect, state: state)

        let trendRect = CGRect(
            x: root.minX + detailInset,
            y: consumptionRect.maxY + sectionGap,
            width: root.width - detailInset * 2,
            height: 198
        )
        drawTrendBoard(in: trendRect, state: state)
    }

    private func drawDetailHero(in rect: CGRect, state: CodexUsageSnapshot) {
        drawGlassPanel(rect, radius: 28, highlighted: false)

        let center = CGPoint(x: rect.midX, y: rect.minY + 118)
        let primaryStatus = quotaStatus(for: state.primaryWindow)
        let secondaryStatus = quotaStatus(for: state.secondaryWindow)
        let outerProgress = animatedSecondaryPercent()
        let innerProgress = animatedPrimaryPercent()

        drawQuotaRing(
            center: center,
            radius: 94,
            width: 22,
            progress: outerProgress,
            color: secondaryStatus.color
        )
        drawQuotaRing(
            center: center,
            radius: 68,
            width: 18,
            progress: innerProgress,
            color: primaryStatus.color
        )

        drawFittedText(
            percentText(outerProgress),
            in: CGRect(x: center.x - 54, y: center.y - 48, width: 108, height: 24),
            font: .systemFont(ofSize: 20, weight: .heavy),
            color: secondaryStatus.color,
            alignment: .center
        )
        drawFittedText(
            percentText(innerProgress),
            in: CGRect(x: center.x - 74, y: center.y - 8, width: 148, height: 48),
            font: .systemFont(ofSize: 42, weight: .heavy),
            color: primaryStatus.color,
            alignment: .center
        )

        let primaryDuration = remainingDuration(state.primaryWindow.resetsAt)
        let secondaryDuration = remainingDuration(state.secondaryWindow.resetsAt)
        let durationFont = NSFont.systemFont(ofSize: 24, weight: .heavy)
        let resetFont = NSFont.systemFont(ofSize: 18, weight: .heavy)
        let primaryDurationRect = CGRect(x: rect.minX + 24, y: rect.maxY - 48, width: 190, height: 34)
        let secondaryDurationRect = CGRect(x: rect.maxX - 214, y: rect.maxY - 48, width: 190, height: 34)

        drawResetClockText(
            resetClock(state.primaryWindow.resetsAt, style: .hourMinute),
            above: primaryDuration,
            countdownRect: primaryDurationRect,
            countdownFont: durationFont,
            resetFont: resetFont,
            alignment: .left
        )
        drawFittedText(
            primaryDuration,
            in: primaryDurationRect,
            font: durationFont,
            color: primaryStatus.color,
            alignment: .left
        )
        drawResetClockText(
            resetClock(state.secondaryWindow.resetsAt, style: .monthDayHourMinute),
            above: secondaryDuration,
            countdownRect: secondaryDurationRect,
            countdownFont: durationFont,
            resetFont: resetFont,
            alignment: .right
        )
        drawFittedText(
            secondaryDuration,
            in: secondaryDurationRect,
            font: durationFont,
            color: secondaryStatus.color,
            alignment: .right
        )
    }

    private func drawQuotaRing(center: CGPoint, radius: CGFloat, width: CGFloat, progress: CGFloat, color: NSColor) {
        let background = NSBezierPath()
        background.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
        NSColor(calibratedRed: 0.68, green: 0.72, blue: 0.76, alpha: 0.44).setStroke()
        background.lineWidth = width
        background.lineCapStyle = .round
        background.stroke()

        let ring = NSBezierPath()
        ring.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: -90,
            endAngle: -90 + 360 * max(0.02, min(progress, 1)),
            clockwise: false
        )

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        let pulse = (sin(animationPhase * 2.0) + 1) / 2
        shadow.shadowColor = color.withAlphaComponent(0.24 + pulse * 0.10)
        shadow.shadowBlurRadius = 12 + pulse * 8
        shadow.shadowOffset = .zero
        shadow.set()
        color.setStroke()
        ring.lineWidth = width
        ring.lineCapStyle = .round
        ring.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawTokenCard(title: String, value: String, subtitle: String, accent: NSColor, in rect: CGRect) {
        drawGlassPanel(rect, radius: 18, highlighted: false)
        accent.withAlphaComponent(0.95).setFill()
        NSBezierPath(ovalIn: CGRect(x: rect.maxX - 30, y: rect.minY + 22, width: 9, height: 9)).fill()
        drawFittedText(
            title,
            in: CGRect(x: rect.minX + 16, y: rect.minY + 20, width: rect.width - 42, height: 24),
            font: .systemFont(ofSize: 18, weight: .heavy),
            color: mutedTextColor,
            alignment: .left
        )
        drawFittedText(
            value,
            in: CGRect(x: rect.minX + 16, y: rect.minY + 54, width: rect.width - 28, height: 36),
            font: .systemFont(ofSize: 32, weight: .heavy),
            color: accent,
            alignment: .left
        )
        drawFittedText(
            subtitle,
            in: CGRect(x: rect.minX + 16, y: rect.minY + 92, width: rect.width - 28, height: 20),
            font: .systemFont(ofSize: 15, weight: .heavy),
            color: mutedTextColor,
            alignment: .left
        )
    }

    private func drawConsumptionBoard(in rect: CGRect, state: CodexUsageSnapshot) {
        drawGlassPanel(rect, radius: 20, highlighted: false)
        drawFittedText(
            "Token 消耗看板",
            in: CGRect(x: rect.minX + 18, y: rect.minY + 18, width: 220, height: 30),
            font: .systemFont(ofSize: 24, weight: .heavy),
            color: textColor,
            alignment: .left
        )
        let metaText = "累计 \(Formatters.tokens(state.month.totalTokens))"
        drawFittedText(
            metaText,
            in: CGRect(x: rect.maxX - 148, y: rect.minY + 20, width: 128, height: 24),
            font: .systemFont(ofSize: 16, weight: .heavy),
            color: mutedTextColor,
            alignment: .right
        )

        let gap: CGFloat = 12
        let cardW = (rect.width - 52 - gap * 2) / 3
        let cardY = rect.minY + 66
        drawMiniStat(title: "今日", value: Formatters.tokens(state.today.totalTokens), raw: Formatters.rawTokens(state.today.totalTokens), color: NSColor(calibratedRed: 0.65, green: 0.55, blue: 1.0, alpha: 1), in: CGRect(x: rect.minX + 18, y: cardY, width: cardW, height: 82))
        drawMiniStat(title: "近 7 天", value: Formatters.tokens(state.sevenDays.totalTokens), raw: Formatters.rawTokens(state.sevenDays.totalTokens), color: sevenDayStatColor, in: CGRect(x: rect.minX + 18 + cardW + gap, y: cardY, width: cardW, height: 82))
        drawMiniStat(title: "本月", value: Formatters.tokens(state.month.totalTokens), raw: Formatters.rawTokens(state.month.totalTokens), color: textColor, in: CGRect(x: rect.minX + 18 + (cardW + gap) * 2, y: cardY, width: cardW, height: 82))
    }

    private func drawMiniStat(title: String, value: String, raw: String, color: NSColor, in rect: CGRect) {
        drawGlassPanel(rect, radius: 14, highlighted: false)
        drawFittedText(title, in: CGRect(x: rect.minX + 14, y: rect.minY + 12, width: rect.width - 28, height: 20), font: .systemFont(ofSize: 16, weight: .heavy), color: mutedTextColor, alignment: .left)
        drawFittedText(value, in: CGRect(x: rect.minX + 14, y: rect.minY + 34, width: rect.width - 28, height: 28), font: .systemFont(ofSize: 24, weight: .heavy), color: color, alignment: .left)
        drawFittedText(raw, in: CGRect(x: rect.minX + 14, y: rect.minY + 62, width: rect.width - 28, height: 16), font: .systemFont(ofSize: 12, weight: .bold), color: mutedTextColor, alignment: .left)
    }

    private func drawTrendBoard(in rect: CGRect, state: CodexUsageSnapshot) {
        drawGlassPanel(rect, radius: 20, highlighted: false)
        drawFittedText(
            "近 7 天趋势",
            in: CGRect(x: rect.minX + 18, y: rect.minY + 16, width: 200, height: 28),
            font: .systemFont(ofSize: 23, weight: .heavy),
            color: textColor,
            alignment: .left
        )
        drawFittedText(
            "合计 \(Formatters.tokens(state.sevenDays.totalTokens))",
            in: CGRect(x: rect.maxX - 168, y: rect.minY + 18, width: 148, height: 24),
            font: .systemFont(ofSize: 15, weight: .heavy),
            color: mutedTextColor,
            alignment: .right
        )

        let chartRect = CGRect(x: rect.minX + 22, y: rect.minY + 58, width: rect.width - 44, height: 96)
        drawTrendChart(in: chartRect, history: state.history)

        let peak = state.history.map(\.totals.totalTokens).max() ?? 0
        let footerY = rect.maxY - 34
        drawFittedText(
            "峰值 \(Formatters.tokens(peak))",
            in: CGRect(x: rect.minX + 24, y: footerY, width: 180, height: 20),
            font: .systemFont(ofSize: 14, weight: .heavy),
            color: mutedTextColor,
            alignment: .left
        )
        drawFittedText(
            "今日 \(Formatters.tokens(state.today.totalTokens))",
            in: CGRect(x: rect.maxX - 204, y: footerY, width: 180, height: 20),
            font: .systemFont(ofSize: 14, weight: .heavy),
            color: mutedTextColor,
            alignment: .right
        )
    }

    private func drawTrendChart(in rect: CGRect, history: [DailyUsagePoint]) {
        trendHoverRegions = []

        NSColor.white.withAlphaComponent(0.36).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()

        guard !history.isEmpty else {
            drawFittedText(
                "--",
                in: rect.insetBy(dx: 18, dy: 26),
                font: .systemFont(ofSize: 22, weight: .heavy),
                color: mutedTextColor,
                alignment: .center
            )
            return
        }

        let maxTokens = max(history.map(\.totals.totalTokens).max() ?? 0, 1)
        let chartRect = CGRect(x: rect.minX + 18, y: rect.minY + 16, width: rect.width - 36, height: rect.height - 46)
        let baseline = chartRect.maxY
        let accent = NSColor(calibratedRed: 0.00, green: 0.62, blue: 0.78, alpha: 1)
        let currentAccent = NSColor(calibratedRed: 0.24, green: 0.42, blue: 0.95, alpha: 1)
        let revealProgress = easedTrendDrawProgress()

        for lineIndex in 0...3 {
            let y = chartRect.minY + chartRect.height * CGFloat(lineIndex) / 3
            let gridPath = NSBezierPath()
            gridPath.move(to: CGPoint(x: chartRect.minX, y: y))
            gridPath.line(to: CGPoint(x: chartRect.maxX, y: y))
            borderColor.withAlphaComponent(lineIndex == 3 ? 0.26 : 0.15).setStroke()
            gridPath.lineWidth = 1
            gridPath.stroke()
        }

        let points: [CGPoint] = history.enumerated().map { index, point in
            let x = history.count == 1
                ? chartRect.midX
                : chartRect.minX + chartRect.width * CGFloat(index) / CGFloat(history.count - 1)
            let percent = CGFloat(Double(point.totals.totalTokens) / Double(maxTokens))
            let y = baseline - chartRect.height * percent
            return CGPoint(x: x, y: y)
        }

        for (index, point) in points.enumerated() {
            let left = index == 0 ? rect.minX : (points[index - 1].x + point.x) / 2
            let right = index == points.count - 1 ? rect.maxX : (point.x + points[index + 1].x) / 2
            trendHoverRegions.append(
                TrendHoverRegion(
                    index: index,
                    rect: CGRect(x: left, y: rect.minY, width: right - left, height: rect.height)
                )
            )
        }

        let visiblePoints = revealedTrendPoints(points, progress: revealProgress)

        if visiblePoints.count > 1 {
            let areaPath = NSBezierPath()
            areaPath.move(to: visiblePoints[0])
            visiblePoints.dropFirst().forEach { areaPath.line(to: $0) }
            areaPath.line(to: CGPoint(x: visiblePoints[visiblePoints.count - 1].x, y: baseline))
            areaPath.line(to: CGPoint(x: visiblePoints[0].x, y: baseline))
            areaPath.close()
            accent.withAlphaComponent(0.18).setFill()
            areaPath.fill()

            let linePath = NSBezierPath()
            linePath.move(to: visiblePoints[0])
            visiblePoints.dropFirst().forEach { linePath.line(to: $0) }

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = accent.withAlphaComponent(0.30)
            shadow.shadowBlurRadius = 6
            shadow.shadowOffset = .zero
            shadow.set()
            accent.setStroke()
            linePath.lineWidth = 3
            linePath.lineCapStyle = .round
            linePath.lineJoinStyle = .round
            linePath.stroke()
            NSGraphicsContext.restoreGraphicsState()
        }

        for (index, point) in points.enumerated() {
            let pointReveal = trendPointReveal(index: index, count: points.count, progress: revealProgress)
            let isVisible = pointReveal > 0.001
            let isHovered = hoveredTrendIndex == index
            let isCurrent = index == points.count - 1
            let pointColor = isCurrent ? currentAccent : accent

            if isHovered, revealProgress >= 0.98 {
                pointColor.withAlphaComponent(0.18).setFill()
                NSBezierPath(ovalIn: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)).fill()

                let guide = NSBezierPath()
                guide.move(to: CGPoint(x: point.x, y: chartRect.minY))
                guide.line(to: CGPoint(x: point.x, y: baseline))
                pointColor.withAlphaComponent(0.42).setStroke()
                guide.lineWidth = 1.5
                guide.stroke()
            }

            if isVisible {
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current?.cgContext.setAlpha(0.35 + 0.65 * pointReveal)
                let dotRadius = 2.4 + 1.8 * pointReveal
                pointColor.setFill()
                NSBezierPath(ovalIn: CGRect(x: point.x - dotRadius, y: point.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)).fill()
                NSColor.white.withAlphaComponent(0.74).setStroke()
                let pointRing = NSBezierPath(ovalIn: CGRect(x: point.x - dotRadius, y: point.y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                pointRing.lineWidth = 1
                pointRing.stroke()
                NSGraphicsContext.restoreGraphicsState()
            }

            drawFittedText(
                history[index].label,
                in: CGRect(x: point.x - 22, y: baseline + 8, width: 44, height: 16),
                font: .systemFont(ofSize: 10, weight: .bold),
                color: mutedTextColor,
                alignment: .center
            )
        }

        if let hoveredTrendIndex,
           revealProgress >= 0.98,
           history.indices.contains(hoveredTrendIndex) {
            drawTrendTooltip(
                for: history[hoveredTrendIndex],
                at: points[hoveredTrendIndex],
                in: rect
            )
        }
    }

    private func revealedTrendPoints(_ points: [CGPoint], progress: CGFloat) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let clamped = max(0, min(progress, 1))
        guard points.count > 1 else {
            return clamped > 0 ? points : []
        }
        if clamped >= 0.999 {
            return points
        }

        let segmentPosition = clamped * CGFloat(points.count - 1)
        let segmentIndex = min(max(0, Int(floor(segmentPosition))), points.count - 2)
        let segmentProgress = segmentPosition - CGFloat(segmentIndex)
        let from = points[segmentIndex]
        let to = points[segmentIndex + 1]
        let interpolated = CGPoint(
            x: from.x + (to.x - from.x) * segmentProgress,
            y: from.y + (to.y - from.y) * segmentProgress
        )

        var visible = Array(points.prefix(segmentIndex + 1))
        visible.append(interpolated)
        return visible
    }

    private func trendPointReveal(index: Int, count: Int, progress: CGFloat) -> CGFloat {
        guard count > 1 else { return progress }
        let clamped = max(0, min(progress, 1))
        let pointStep = CGFloat(index) / CGFloat(count - 1)
        let revealWindow = max(0.08, 0.45 / CGFloat(count - 1))
        return max(0, min((clamped - pointStep) / revealWindow, 1))
    }

    private func drawTrendTooltip(for point: DailyUsagePoint, at anchor: CGPoint, in rect: CGRect) {
        let width: CGFloat = 154
        let height: CGFloat = 52
        let x = min(max(rect.minX + 8, anchor.x - width / 2), rect.maxX - width - 8)
        let y = max(rect.minY + 8, anchor.y - height - 12)
        let tooltipRect = CGRect(x: x, y: y, width: width, height: height)
        let path = NSBezierPath(roundedRect: tooltipRect, xRadius: 13, yRadius: 13)

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
        shadow.shadowBlurRadius = 14
        shadow.shadowOffset = CGSize(width: 0, height: 6)
        shadow.set()
        NSColor.white.withAlphaComponent(0.92).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        borderColor.withAlphaComponent(0.38).setStroke()
        path.lineWidth = 1
        path.stroke()

        drawFittedText(
            point.dayID,
            in: CGRect(x: tooltipRect.minX + 12, y: tooltipRect.minY + 8, width: tooltipRect.width - 24, height: 16),
            font: .systemFont(ofSize: 12, weight: .bold),
            color: mutedTextColor,
            alignment: .left
        )
        drawFittedText(
            "\(Formatters.tokens(point.totals.totalTokens)) Token",
            in: CGRect(x: tooltipRect.minX + 12, y: tooltipRect.minY + 25, width: tooltipRect.width - 24, height: 20),
            font: .systemFont(ofSize: 16, weight: .heavy),
            color: textColor,
            alignment: .left
        )
    }

    private func drawResetClockText(
        _ text: String,
        above countdown: String,
        countdownRect: CGRect,
        countdownFont: NSFont,
        resetFont: NSFont,
        alignment: NSTextAlignment
    ) {
        let y = countdownRect.minY - 25
        if alignment == .left {
            let width = min(countdownRect.width + 48, max(38, measuredTextWidth(text, font: resetFont) + 8))
            drawFittedText(
                text,
                in: CGRect(x: countdownRect.minX, y: y, width: width, height: 24),
                font: resetFont,
                color: mutedTextColor.withAlphaComponent(0.82),
                alignment: .left
            )
        } else {
            drawRightAlignedAuxText(
                text,
                rightEdge: valueRightEdge(countdown, in: countdownRect, font: countdownFont, alignment: alignment),
                y: y,
                maxWidth: countdownRect.width + 48,
                font: resetFont
            )
        }
    }

    private func drawRightAlignedAuxText(_ text: String, rightEdge: CGFloat, y: CGFloat, maxWidth: CGFloat, font: NSFont) {
        let width = min(maxWidth, max(38, measuredTextWidth(text, font: font) + 8))
        drawFittedText(
            text,
            in: CGRect(x: rightEdge - width, y: y, width: width, height: 24),
            font: font,
            color: mutedTextColor.withAlphaComponent(0.82),
            alignment: .right
        )
    }

    private func valueRightEdge(_ text: String, in rect: CGRect, font: NSFont, alignment: NSTextAlignment) -> CGFloat {
        switch alignment {
        case .right:
            return rect.maxX
        case .center:
            let width = min(rect.width, measuredTextWidth(text, font: font))
            return rect.midX + width / 2
        default:
            return min(rect.maxX, rect.minX + measuredTextWidth(text, font: font))
        }
    }

    private func measuredTextWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func drawInfoCard(
        title: String,
        resetTime: String,
        percent: String,
        remaining: String,
        in rect: CGRect,
        style: InfoCardValueStyle,
        tint: NSColor?
    ) {
        drawGlassPanel(rect, radius: 26, highlighted: false, tint: tint)
        let valueFont = NSFont.systemFont(ofSize: 26, weight: .heavy)
        let valueY = rect.minY + 58
        let leftInset: CGFloat = 26
        let rightInset: CGFloat = 18
        let dotCenterX = rect.minX + (style == .longDuration ? 112 : 120)
        let dotRect = CGRect(x: dotCenterX - 7, y: valueY, width: 14, height: 36)
        let percentRect = CGRect(
            x: rect.minX + leftInset,
            y: valueY,
            width: dotRect.minX - rect.minX - leftInset - 6,
            height: 36
        )
        let remainingX = dotRect.maxX + 8
        let remainingRect = CGRect(
            x: remainingX,
            y: valueY,
            width: rect.maxX - rightInset - remainingX,
            height: 36
        )
        let resetFont = NSFont.systemFont(ofSize: 19, weight: .bold)
        let resetWidth = min(176, max(54, measuredTextWidth(resetTime, font: resetFont) + 8))
        let titleRect = CGRect(
            x: rect.minX + 26,
            y: rect.minY + 22,
            width: max(72, rect.width - 26 - rightInset - resetWidth - 16),
            height: 28
        )
        let resetRect = CGRect(
            x: rect.maxX - rightInset - resetWidth,
            y: rect.minY + 24,
            width: resetWidth,
            height: 24
        )
        drawFittedText(
            title,
            in: titleRect,
            font: .systemFont(ofSize: 24, weight: .heavy),
            color: mutedTextColor,
            alignment: .left
        )
        drawFittedText(
            resetTime,
            in: resetRect,
            font: resetFont,
            color: mutedTextColor.withAlphaComponent(0.82),
            alignment: .right
        )
        drawFittedText(
            percent,
            in: percentRect,
            font: valueFont,
            color: textColor,
            alignment: .left
        )
        drawFittedText(
            "•",
            in: dotRect,
            font: .systemFont(ofSize: 28, weight: .black),
            color: textColor,
            alignment: .center
        )
        drawFittedText(
            remaining,
            in: remainingRect,
            font: valueFont,
            color: textColor,
            alignment: .right
        )
    }

    private func drawGlassPanel(_ rect: CGRect, radius: CGFloat, highlighted: Bool, tint: NSColor? = nil) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = CGSize(width: 0, height: 8)
        shadow.set()
        (highlighted ? hotGlassFill : glassFill).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        if let tint {
            tint.withAlphaComponent(highlighted ? 0.16 : 0.10).setFill()
            path.fill()
        }

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        let topGlow = NSGradient(colors: [
            NSColor.white.withAlphaComponent(0.25),
            NSColor.white.withAlphaComponent(0.11),
            NSColor.white.withAlphaComponent(0.00)
        ])
        topGlow?.draw(in: rect, angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        let stroke = tint?.withAlphaComponent(0.34) ?? (highlighted ? hotBorderColor : borderColor)
        stroke.setStroke()
        path.lineWidth = highlighted ? 1.8 : 1.1
        path.stroke()

        let shine = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: radius - 2, yRadius: radius - 2)
        NSColor.white.withAlphaComponent(highlighted ? 0.26 : 0.22).setStroke()
        shine.lineWidth = 1
        shine.stroke()
    }

    private func hasQuotaData(_ state: CodexUsageSnapshot) -> Bool {
        state.primaryWindow.remainingPercent != nil || state.secondaryWindow.remainingPercent != nil
    }

    private func drawStatusLight(in rect: CGRect, color: NSColor, animated: Bool) {
        let pulse = animated ? (sin(animationPhase * 2.2) + 1) / 2 : 0
        let bulbRect = rect.insetBy(dx: 5, dy: 5)

        if animated {
            color.withAlphaComponent(0.08 + pulse * 0.06).setFill()
            let haloOutset = 3 + pulse * 5
            NSBezierPath(ovalIn: bulbRect.insetBy(dx: -haloOutset, dy: -haloOutset)).fill()
        }

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color.withAlphaComponent(animated ? 0.46 + pulse * 0.14 : 0.16)
        shadow.shadowBlurRadius = animated ? 6 + pulse * 5 : 3
        shadow.shadowOffset = .zero
        shadow.set()

        color.setFill()
        NSBezierPath(ovalIn: bulbRect).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(animated ? 0.56 : 0.42).setStroke()
        let ring = NSBezierPath(ovalIn: bulbRect)
        ring.lineWidth = 1.8
        ring.stroke()
    }

    private func drawMeter(in rect: CGRect, remainingPercent: Double?, color: NSColor, animated: Bool) {
        let progress = CGFloat(max(0, min((remainingPercent ?? 0) / 100, 1)))
        let circle = NSBezierPath(ovalIn: rect)

        let bgGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.90, green: 0.94, blue: 0.96, alpha: 0.72),
            NSColor(calibratedRed: 0.60, green: 0.68, blue: 0.75, alpha: 0.52)
        ])
        bgGradient?.draw(in: circle, angle: -42)

        NSGraphicsContext.saveGraphicsState()
        circle.addClip()

        if remainingPercent != nil {
            let fillHeight = max(progress * rect.height, progress > 0 ? 9 : 0)
            let fillRect = CGRect(x: rect.minX, y: rect.maxY - fillHeight, width: rect.width, height: fillHeight)
            color.withAlphaComponent(0.62).setFill()
            fillRect.fill()

            let wave = NSBezierPath()
            let baseY = rect.maxY - fillHeight + 4
            let phase = animated ? animationPhase * 2.7 : 0
            wave.move(to: CGPoint(x: rect.minX, y: baseY))
            for step in 0...28 {
                let x = rect.minX + rect.width * CGFloat(step) / 28
                let y = baseY + sin(CGFloat(step) / 28 * CGFloat.pi * 3.2 + phase) * 10
                wave.line(to: CGPoint(x: x, y: y))
            }
            wave.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
            wave.line(to: CGPoint(x: rect.minX, y: rect.maxY))
            wave.close()
            color.withAlphaComponent(0.78).setFill()
            wave.fill()
        }
        NSGraphicsContext.restoreGraphicsState()

        let outerRimWidth: CGFloat = 2.2
        let innerRimWidth: CGFloat = 5.0

        let rim = NSBezierPath(ovalIn: rect.insetBy(dx: outerRimWidth / 2, dy: outerRimWidth / 2))
        NSColor(calibratedRed: 0.42, green: 0.48, blue: 0.54, alpha: 0.54).setStroke()
        rim.lineWidth = outerRimWidth
        rim.stroke()

        let innerRimInset = outerRimWidth + innerRimWidth / 2
        let innerRim = NSBezierPath(ovalIn: rect.insetBy(dx: innerRimInset, dy: innerRimInset))
        NSColor.white.withAlphaComponent(0.46).setStroke()
        innerRim.lineWidth = innerRimWidth
        innerRim.stroke()

        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        NSColor.white.withAlphaComponent(0.34).setFill()
        let highlightRect = CGRect(x: rect.minX + 54, y: rect.minY + 34, width: 62, height: 30)
        let highlightCenter = CGPoint(x: highlightRect.midX, y: highlightRect.midY)
        let highlight = NSBezierPath(ovalIn: highlightRect)
        highlight.transform(using: AffineTransform(translationByX: -highlightCenter.x, byY: -highlightCenter.y))
        highlight.transform(using: AffineTransform(rotationByDegrees: -22))
        highlight.transform(using: AffineTransform(translationByX: highlightCenter.x, byY: highlightCenter.y))
        highlight.fill()
        NSGraphicsContext.restoreGraphicsState()

        drawFittedText(
            Formatters.remainingPercent(UsageWindow(usedPercent: remainingPercent.map { 100 - $0 }, windowMinutes: nil, resetsAt: nil)),
            in: CGRect(x: rect.minX + 36, y: rect.midY - 48, width: rect.width - 72, height: 68),
            font: .systemFont(ofSize: 58, weight: .heavy),
            color: NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.13, alpha: 1),
            alignment: .center
        )
        drawFittedText(
            "剩余",
            in: CGRect(x: rect.minX + 64, y: rect.midY + 24, width: rect.width - 128, height: 30),
            font: .systemFont(ofSize: 24, weight: .heavy),
            color: NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.24, alpha: 1),
            alignment: .center
        )
    }

    private func drawIconButton(in rect: CGRect, kind: IconKind, spinning: Bool, active: Bool = false) {
        if kind == .close {
            drawCloseButtonBackground(in: rect)
        } else if kind == .pin, active {
            drawGlassPanel(rect, radius: 18, highlighted: false, tint: green.withAlphaComponent(0.16))
        } else {
            drawGlassPanel(rect, radius: 18, highlighted: false)
        }

        let path = NSBezierPath()
        switch kind {
        case .refresh:
            if drawSystemSymbol("arrow.clockwise", in: rect, spinning: spinning) {
                return
            }
            drawRefreshFallbackIcon(in: rect, spinning: spinning)
            return
        case .pin:
            let symbolName = active ? "pin.fill" : "pin"
            let color = active ? green.withAlphaComponent(0.96) : textColor.withAlphaComponent(0.92)
            if drawSystemSymbol(symbolName, in: rect, spinning: false, color: color, rotationDegrees: 180) {
                return
            }
            drawPinFallbackIcon(in: rect, active: active)
            return
        case .minus:
            path.move(to: CGPoint(x: rect.minX + 17, y: rect.midY))
            path.line(to: CGPoint(x: rect.maxX - 17, y: rect.midY))
        case .close:
            path.move(to: CGPoint(x: rect.minX + 16, y: rect.minY + 16))
            path.line(to: CGPoint(x: rect.maxX - 16, y: rect.maxY - 16))
            path.move(to: CGPoint(x: rect.maxX - 16, y: rect.minY + 16))
            path.line(to: CGPoint(x: rect.minX + 16, y: rect.maxY - 16))
        }

        if spinning {
            path.transform(using: AffineTransform(translationByX: -rect.midX, byY: -rect.midY))
            path.transform(using: AffineTransform(rotationByDegrees: -Double(animationPhase * 220)))
            path.transform(using: AffineTransform(translationByX: rect.midX, byY: rect.midY))
        }

        textColor.withAlphaComponent(0.9).setStroke()
        path.lineWidth = 3.2
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.stroke()
    }

    private func drawCloseButtonBackground(in rect: CGRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 18, yRadius: 18)
        NSColor(calibratedRed: 0.94, green: 0.20, blue: 0.25, alpha: 0.88).setFill()
        path.fill()

        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        NSColor.white.withAlphaComponent(0.10).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 16, yRadius: 16).fill()
        NSColor.black.withAlphaComponent(0.12).setFill()
        CGRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor(calibratedRed: 1.0, green: 0.58, blue: 0.62, alpha: 0.88).setStroke()
        path.lineWidth = 1.6
        path.stroke()
    }

    private func drawSystemSymbol(
        _ symbolName: String,
        in rect: CGRect,
        spinning: Bool,
        color: NSColor? = nil,
        rotationDegrees: CGFloat = 0
    ) -> Bool {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return false
        }

        let pointSize = rect.width * 0.44
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let configuredImage = image.withSymbolConfiguration(configuration) ?? image
        let tintedImage = tintedSymbolImage(configuredImage, color: color ?? textColor.withAlphaComponent(0.92))
        let side = rect.width * 0.46
        let drawRect = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)

        NSGraphicsContext.saveGraphicsState()
        if spinning || rotationDegrees != 0 {
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            let spinDegrees: CGFloat = spinning ? -animationPhase * 220 : 0
            transform.rotate(byDegrees: Double(rotationDegrees + spinDegrees))
            transform.translateX(by: -rect.midX, yBy: -rect.midY)
            transform.concat()
        }
        tintedImage.draw(in: drawRect, from: CGRect(origin: .zero, size: tintedImage.size), operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
        return true
    }

    private func tintedSymbolImage(_ image: NSImage, color: NSColor) -> NSImage {
        let output = NSImage(size: image.size)
        output.lockFocus()
        let rect = CGRect(origin: .zero, size: image.size)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        color.setFill()
        rect.fill(using: .sourceAtop)
        output.unlockFocus()
        output.isTemplate = false
        return output
    }

    private func drawRefreshFallbackIcon(in rect: CGRect, spinning: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = rect.width * 0.25
        let startAngle: CGFloat = -54
        let endAngle: CGFloat = 252
        let samples = 34
        let iconPath = NSBezierPath()

        for index in 0...samples {
            let t = CGFloat(index) / CGFloat(samples)
            let degrees = startAngle + (endAngle - startAngle) * t
            let radians = degrees * .pi / 180
            let point = CGPoint(
                x: center.x + cos(radians) * radius,
                y: center.y + sin(radians) * radius
            )
            if index == 0 {
                iconPath.move(to: point)
            } else {
                iconPath.line(to: point)
            }
        }

        let arrowAngle = startAngle * .pi / 180
        let tip = CGPoint(
            x: center.x + cos(arrowAngle) * radius,
            y: center.y + sin(arrowAngle) * radius
        )
        let tangent = CGPoint(x: -sin(arrowAngle), y: cos(arrowAngle))
        let radial = CGPoint(x: cos(arrowAngle), y: sin(arrowAngle))
        let arrowSize = rect.width * 0.13

        iconPath.move(to: tip)
        iconPath.line(to: CGPoint(
            x: tip.x - tangent.x * arrowSize - radial.x * arrowSize * 0.22,
            y: tip.y - tangent.y * arrowSize - radial.y * arrowSize * 0.22
        ))
        iconPath.move(to: tip)
        iconPath.line(to: CGPoint(
            x: tip.x - radial.x * arrowSize * 0.30 + tangent.x * arrowSize * 0.14,
            y: tip.y - radial.y * arrowSize * 0.30 + tangent.y * arrowSize * 0.14
        ))

        if spinning {
            iconPath.transform(using: AffineTransform(translationByX: -center.x, byY: -center.y))
            iconPath.transform(using: AffineTransform(rotationByDegrees: -Double(animationPhase * 220)))
            iconPath.transform(using: AffineTransform(translationByX: center.x, byY: center.y))
        }

        textColor.withAlphaComponent(0.92).setStroke()
        iconPath.lineWidth = 3.0
        iconPath.lineCapStyle = .round
        iconPath.lineJoinStyle = .round
        iconPath.stroke()
    }

    private func drawPinFallbackIcon(in rect: CGRect, active: Bool) {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let pinPath = NSBezierPath()
        pinPath.move(to: CGPoint(x: center.x - 8, y: center.y - 12))
        pinPath.curve(
            to: CGPoint(x: center.x + 8, y: center.y - 12),
            controlPoint1: CGPoint(x: center.x - 2, y: center.y - 18),
            controlPoint2: CGPoint(x: center.x + 2, y: center.y - 18)
        )
        pinPath.line(to: CGPoint(x: center.x + 4, y: center.y + 2))
        pinPath.line(to: CGPoint(x: center.x + 12, y: center.y + 8))
        pinPath.move(to: CGPoint(x: center.x - 12, y: center.y + 8))
        pinPath.line(to: CGPoint(x: center.x - 4, y: center.y + 2))
        pinPath.line(to: CGPoint(x: center.x, y: center.y + 17))
        pinPath.transform(using: AffineTransform(translationByX: -center.x, byY: -center.y))
        pinPath.transform(using: AffineTransform(rotationByDegrees: 180))
        pinPath.transform(using: AffineTransform(translationByX: center.x, byY: center.y))

        (active ? green.withAlphaComponent(0.96) : textColor.withAlphaComponent(0.92)).setStroke()
        pinPath.lineWidth = 3.0
        pinPath.lineCapStyle = .round
        pinPath.lineJoinStyle = .round
        pinPath.stroke()
    }

    private func drawDetailButton(title: String, in rect: CGRect) {
        drawGlassPanel(rect, radius: 17, highlighted: false)
        let kern: CGFloat = rect.width < 120 ? 0 : 3.2
        drawSpacedText(
            title,
            in: rect.insetBy(dx: 14, dy: 7),
            font: .systemFont(ofSize: 19, weight: .heavy),
            color: textColor,
            alignment: .center,
            kern: kern
        )
    }

    private func quotaStatus(for window: UsageWindow) -> (label: String, color: NSColor) {
        guard let remaining = window.remainingPercent else {
            return ("读取中", mutedTextColor)
        }
        if remaining < 10 {
            return ("红灯", red)
        }
        if remaining < 20 {
            return ("黄灯", yellow)
        }
        return ("绿灯", green)
    }

    private func overallQuotaStatus(for state: CodexUsageSnapshot) -> (label: String, color: NSColor) {
        if let sevenDayRemaining = state.secondaryWindow.remainingPercent,
           sevenDayRemaining <= 0 {
            return ("红灯", red)
        }
        return quotaStatus(for: state.primaryWindow)
    }

    private func resetClock(_ date: Date?, style: ResetClockStyle) -> String {
        guard let date else { return "--" }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        formatter.dateFormat = style == .hourMinute ? "HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private func resetDescription(_ date: Date?) -> String {
        guard let date else { return "--" }
        let totalMinutes = max(0, Int(date.timeIntervalSinceNow / 60))
        if totalMinutes == 0 {
            return "即将重置"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        }
        return "\(minutes)分钟"
    }

    private func remainingDuration(_ date: Date?) -> String {
        guard let date else { return "--" }
        let totalMinutes = max(0, Int(date.timeIntervalSinceNow / 60))
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            if hours == 0, minutes > 0 {
                return "\(days)天\(minutes)分钟"
            }
            if hours == 0 {
                return "\(days)天"
            }
            return "\(days)天\(hours)小时"
        }
        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        }
        return "\(minutes)分钟"
    }

    private func startAnimation() {
        guard animationTimer == nil else { return }
        let frameInterval: CGFloat = 1.0 / 60.0
        let timer = Timer(timeInterval: TimeInterval(frameInterval), repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.window?.isVisible == true else { return }
            self.animationPhase += frameInterval
            if self.detailRingProgress < 1 {
                self.detailRingProgress = min(1, self.detailRingProgress + frameInterval / self.detailRingDuration)
            }
            if self.trendDrawProgress < 1 {
                self.trendDrawProgress = min(1, self.trendDrawProgress + frameInterval / self.trendDrawDuration)
            }
            self.needsDisplay = true
        }
        RunLoop.main.add(timer, forMode: .common)
        animationTimer = timer
    }

    private func designTransform() -> (scale: CGFloat, origin: CGPoint) {
        let scale = min(bounds.width / designSize.width, bounds.height / designSize.height)
        let drawnSize = CGSize(width: designSize.width * scale, height: designSize.height * scale)
        return (
            max(0.1, scale),
            CGPoint(x: (bounds.width - drawnSize.width) / 2, y: (bounds.height - drawnSize.height) / 2)
        )
    }

    private func designPoint(from point: CGPoint) -> CGPoint {
        let transform = designTransform()
        return CGPoint(
            x: (point.x - transform.origin.x) / transform.scale,
            y: (point.y - transform.origin.y) / transform.scale
        )
    }

    private func drawFittedText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor, alignment: NSTextAlignment) {
        guard rect.width > 2, rect.height > 2 else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail

        var size = font.pointSize
        var fittedFont = font
        while size > 8 {
            let candidate = NSFont(descriptor: font.fontDescriptor, size: size) ?? font
            let attributes: [NSAttributedString.Key: Any] = [.font: candidate]
            let measured = (text as NSString).size(withAttributes: attributes)
            let lineHeight = candidate.ascender - candidate.descender + candidate.leading
            if measured.width <= rect.width + 0.5, lineHeight <= rect.height + 0.5 {
                fittedFont = candidate
                break
            }
            size -= 1
            fittedFont = candidate
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: fittedFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        (text as NSString).draw(in: rect, withAttributes: attributes)
    }

    private func drawSpacedText(_ text: String, in rect: CGRect, font: NSFont, color: NSColor, alignment: NSTextAlignment, kern: CGFloat) {
        guard rect.width > 2, rect.height > 2 else { return }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        paragraph.lineBreakMode = .byTruncatingTail

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .kern: kern
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let measured = attributed.boundingRect(
            with: CGSize(width: rect.width, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        let drawRect = CGRect(
            x: rect.minX,
            y: rect.midY - ceil(measured.height) / 2,
            width: rect.width,
            height: ceil(measured.height) + 2
        )
        attributed.draw(in: drawRect)
    }
}

private enum IconKind {
    case refresh
    case pin
    case minus
    case close
}

private enum InfoCardValueStyle {
    case shortDuration
    case longDuration
}

private enum ResetClockStyle {
    case hourMinute
    case monthDayHourMinute
}

private struct TrendHoverRegion {
    let index: Int
    let rect: CGRect
}
