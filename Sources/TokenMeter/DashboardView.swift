import AppKit

final class DashboardView: NSView {
    var onRefresh: (() -> Void)?
    var onHide: (() -> Void)?
    var onClose: (() -> Void)?
    var onDetailModeChange: ((Bool) -> Void)?

    private let store: CodexUsageStore
    private var isShowingDetails = false

    private var refreshButtonRect = CGRect.zero
    private var hideButtonRect = CGRect.zero
    private var closeButtonRect = CGRect.zero
    private var detailButtonRect = CGRect.zero
    private let compactDesignSize = CGSize(width: 680, height: 520)
    private let detailDesignSize = CGSize(width: 680, height: 1_000)
    private var designSize: CGSize {
        isShowingDetails ? detailDesignSize : compactDesignSize
    }
    private var animationPhase: CGFloat = 0
    private var animationTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private var trendHoverRegions: [TrendHoverRegion] = []
    private var hoveredTrendIndex: Int?

    private let panelFill = NSColor(calibratedRed: 0.16, green: 0.19, blue: 0.22, alpha: 0.86)
    private let glassFill = NSColor(calibratedRed: 0.28, green: 0.32, blue: 0.36, alpha: 0.46)
    private let hotGlassFill = NSColor(calibratedRed: 0.48, green: 0.18, blue: 0.22, alpha: 0.40)
    private let borderColor = NSColor(calibratedRed: 0.82, green: 0.88, blue: 0.94, alpha: 0.38)
    private let hotBorderColor = NSColor(calibratedRed: 1.0, green: 0.36, blue: 0.45, alpha: 0.84)
    private let textColor = NSColor(calibratedRed: 0.95, green: 0.97, blue: 1.0, alpha: 1)
    private let mutedTextColor = NSColor(calibratedRed: 0.73, green: 0.79, blue: 0.85, alpha: 1)
    private let red = NSColor(calibratedRed: 1.0, green: 0.31, blue: 0.38, alpha: 1)
    private let yellow = NSColor(calibratedRed: 1.0, green: 0.78, blue: 0.32, alpha: 1)
    private let green = NSColor(calibratedRed: 0.33, green: 0.92, blue: 0.54, alpha: 1)
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
        if hideButtonRect.contains(point) {
            onHide?()
            return
        }
        if closeButtonRect.contains(point) {
            onClose?()
            return
        }
        if detailButtonRect.contains(point) {
            isShowingDetails.toggle()
            onDetailModeChange?(isShowingDetails)
            needsDisplay = true
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
        guard isShowingDetails else { return }
        isShowingDetails = false
        clearTrendHover()
        onDetailModeChange?(false)
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        refreshButtonRect = .zero
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
        drawChrome(in: root)
        drawHeader(in: root, state: store.snapshot)

        if isShowingDetails {
            drawDetails(in: root)
        } else {
            drawQuotaContent(in: root, state: store.snapshot)
        }
        NSGraphicsContext.restoreGraphicsState()
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
        NSColor.black.withAlphaComponent(0.03).setFill()
        rect.fill()
        NSColor.white.withAlphaComponent(0.075).setFill()
        NSBezierPath(roundedRect: rect.insetBy(dx: 12, dy: 12), xRadius: radius - 10, yRadius: radius - 10).fill()
        NSGraphicsContext.restoreGraphicsState()

        let inner = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: radius - 2, yRadius: radius - 2)
        borderColor.setStroke()
        inner.lineWidth = 2
        inner.stroke()
    }

    private func drawHeader(in root: CGRect, state: CodexUsageSnapshot) {
        let status = quotaStatus(for: state.primaryWindow)
        let dotOuter = CGRect(x: root.minX + 44, y: root.minY + 51, width: 34, height: 34)
        drawStatusLight(in: dotOuter, color: status.color)

        drawFittedText(
            "Codex 额度",
            in: CGRect(x: root.minX + 94, y: root.minY + 36, width: 250, height: 42),
            font: .systemFont(ofSize: 32, weight: .heavy),
            color: textColor,
            alignment: .left
        )
        drawFittedText(
            (state.planType ?? "FREE").uppercased(),
            in: CGRect(x: root.minX + 96, y: root.minY + 78, width: 230, height: 28),
            font: .systemFont(ofSize: 20, weight: .heavy),
            color: mutedTextColor,
            alignment: .left
        )

        let buttonSize: CGFloat = 52
        let gap: CGFloat = 14
        closeButtonRect = CGRect(x: root.maxX - 44 - buttonSize, y: root.minY + 45, width: buttonSize, height: buttonSize)
        hideButtonRect = CGRect(x: closeButtonRect.minX - gap - buttonSize, y: closeButtonRect.minY, width: buttonSize, height: buttonSize)
        refreshButtonRect = CGRect(x: hideButtonRect.minX - gap - buttonSize, y: closeButtonRect.minY, width: buttonSize, height: buttonSize)

        if isShowingDetails {
            detailButtonRect = CGRect(x: refreshButtonRect.minX - gap - 88, y: closeButtonRect.minY, width: 88, height: buttonSize)
            drawDetailButton(title: "返回", in: detailButtonRect)
        }
        drawIconButton(in: refreshButtonRect, kind: .refresh, spinning: store.isRefreshing)
        drawIconButton(in: hideButtonRect, kind: .minus, spinning: false)
        drawIconButton(in: closeButtonRect, kind: .close, spinning: false)
    }

    private func drawQuotaContent(in root: CGRect, state: CodexUsageSnapshot) {
        let status = quotaStatus(for: state.primaryWindow)
        let secondaryStatus = quotaStatus(for: state.secondaryWindow)
        let meterRect = CGRect(x: root.minX + 62, y: root.minY + 190, width: 204, height: 204)
        drawMeter(in: meterRect, remainingPercent: state.primaryWindow.remainingPercent, color: status.color)

        let cardX = root.minX + 322
        let cardWidth = root.maxX - cardX - 36

        drawInfoCard(
            title: "5小时窗口",
            value: "\(Formatters.remainingPercent(state.primaryWindow)) · \(resetDescription(state.primaryWindow.resetsAt))",
            in: CGRect(x: cardX, y: root.minY + 132, width: cardWidth, height: 106),
            tint: state.primaryWindow.remainingPercent == nil ? nil : status.color
        )
        drawInfoCard(
            title: "7天窗口",
            value: "\(Formatters.remainingPercent(state.secondaryWindow)) · \(resetDescription(state.secondaryWindow.resetsAt))",
            in: CGRect(x: cardX, y: root.minY + 260, width: cardWidth, height: 106),
            tint: state.secondaryWindow.remainingPercent == nil ? nil : secondaryStatus.color
        )
        detailButtonRect = CGRect(x: cardX, y: root.minY + 386, width: cardWidth, height: 56)
        drawDetailButton(title: "详情", in: detailButtonRect)
    }

    private func drawDetails(in root: CGRect) {
        let state = store.snapshot
        let primaryStatus = quotaStatus(for: state.primaryWindow)
        let secondaryStatus = quotaStatus(for: state.secondaryWindow)
        let heroRect = CGRect(x: root.minX + 34, y: root.minY + 132, width: root.width - 68, height: 250)
        drawDetailHero(in: heroRect, state: state)

        let cardGap: CGFloat = 14
        let cardY = root.minY + 406
        let cardW = (root.width - 68 - cardGap * 2) / 3
        drawTokenCard(
            title: "5 小时余额",
            value: Formatters.remainingPercent(state.primaryWindow),
            subtitle: "已用 \(Formatters.usedPercent(state.primaryWindow.usedPercent))",
            accent: primaryStatus.color,
            in: CGRect(x: root.minX + 34, y: cardY, width: cardW, height: 120)
        )
        drawTokenCard(
            title: "7 天余额",
            value: Formatters.remainingPercent(state.secondaryWindow),
            subtitle: "已用 \(Formatters.usedPercent(state.secondaryWindow.usedPercent))",
            accent: secondaryStatus.color,
            in: CGRect(x: root.minX + 34 + cardW + cardGap, y: cardY, width: cardW, height: 120)
        )
        drawTokenCard(
            title: "今日 Token",
            value: Formatters.tokens(state.today.totalTokens),
            subtitle: "本月 \(Formatters.tokens(state.month.totalTokens))",
            accent: textColor,
            in: CGRect(x: root.minX + 34 + (cardW + cardGap) * 2, y: cardY, width: cardW, height: 120)
        )

        drawConsumptionBoard(in: CGRect(x: root.minX + 34, y: root.minY + 548, width: root.width - 68, height: 170), state: state)
        drawTrendBoard(in: CGRect(x: root.minX + 34, y: root.minY + 740, width: root.width - 68, height: 198), state: state)
    }

    private func drawDetailHero(in rect: CGRect, state: CodexUsageSnapshot) {
        drawGlassPanel(rect, radius: 28, highlighted: false)

        let center = CGPoint(x: rect.midX, y: rect.minY + 118)
        let primaryStatus = quotaStatus(for: state.primaryWindow)
        let secondaryStatus = quotaStatus(for: state.secondaryWindow)
        let outerProgress = CGFloat((state.secondaryWindow.remainingPercent ?? 0) / 100)
        let innerProgress = CGFloat((state.primaryWindow.remainingPercent ?? 0) / 100)

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
            Formatters.remainingPercent(state.secondaryWindow),
            in: CGRect(x: center.x - 54, y: center.y - 48, width: 108, height: 24),
            font: .systemFont(ofSize: 20, weight: .heavy),
            color: secondaryStatus.color,
            alignment: .center
        )
        drawFittedText(
            Formatters.remainingPercent(state.primaryWindow),
            in: CGRect(x: center.x - 74, y: center.y - 8, width: 148, height: 48),
            font: .systemFont(ofSize: 42, weight: .heavy),
            color: primaryStatus.color,
            alignment: .center
        )

        drawFittedText(
            remainingDuration(state.primaryWindow.resetsAt),
            in: CGRect(x: rect.minX + 24, y: rect.maxY - 48, width: 190, height: 34),
            font: .systemFont(ofSize: 24, weight: .heavy),
            color: primaryStatus.color,
            alignment: .left
        )
        drawFittedText(
            remainingDuration(state.secondaryWindow.resetsAt),
            in: CGRect(x: rect.maxX - 214, y: rect.maxY - 48, width: 190, height: 34),
            font: .systemFont(ofSize: 24, weight: .heavy),
            color: secondaryStatus.color,
            alignment: .right
        )
    }

    private func drawQuotaRing(center: CGPoint, radius: CGFloat, width: CGFloat, progress: CGFloat, color: NSColor) {
        let background = NSBezierPath()
        background.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360, clockwise: false)
        NSColor(calibratedRed: 0.18, green: 0.20, blue: 0.25, alpha: 0.78).setStroke()
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
        shadow.shadowColor = color.withAlphaComponent(0.32)
        shadow.shadowBlurRadius = 16
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
        let metaText = state.accountUsageFetchedAt == nil
            ? "样本 \(state.eventCount.formatted())"
            : "累计 \(Formatters.tokens(state.allTime.totalTokens))"
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
        drawMiniStat(title: "近 7 天", value: Formatters.tokens(state.sevenDays.totalTokens), raw: Formatters.rawTokens(state.sevenDays.totalTokens), color: NSColor(calibratedRed: 0.36, green: 0.90, blue: 0.94, alpha: 1), in: CGRect(x: rect.minX + 18 + cardW + gap, y: cardY, width: cardW, height: 82))
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

        NSColor(calibratedRed: 0.16, green: 0.15, blue: 0.22, alpha: 0.54).setFill()
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
        let accent = NSColor(calibratedRed: 0.36, green: 0.90, blue: 0.94, alpha: 1)
        let currentAccent = NSColor(calibratedRed: 0.65, green: 0.55, blue: 1.0, alpha: 1)

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

        if points.count > 1 {
            let areaPath = NSBezierPath()
            areaPath.move(to: points[0])
            points.dropFirst().forEach { areaPath.line(to: $0) }
            areaPath.line(to: CGPoint(x: points[points.count - 1].x, y: baseline))
            areaPath.line(to: CGPoint(x: points[0].x, y: baseline))
            areaPath.close()
            accent.withAlphaComponent(0.14).setFill()
            areaPath.fill()

            let linePath = NSBezierPath()
            linePath.move(to: points[0])
            points.dropFirst().forEach { linePath.line(to: $0) }

            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = accent.withAlphaComponent(0.35)
            shadow.shadowBlurRadius = 8
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
            let isHovered = hoveredTrendIndex == index
            let isCurrent = index == points.count - 1
            let pointColor = isCurrent ? currentAccent : accent
            if isHovered {
                pointColor.withAlphaComponent(0.18).setFill()
                NSBezierPath(ovalIn: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20)).fill()

                let guide = NSBezierPath()
                guide.move(to: CGPoint(x: point.x, y: chartRect.minY))
                guide.line(to: CGPoint(x: point.x, y: baseline))
                pointColor.withAlphaComponent(0.42).setStroke()
                guide.lineWidth = 1.5
                guide.stroke()
            }

            pointColor.setFill()
            NSBezierPath(ovalIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8)).fill()
            NSColor.white.withAlphaComponent(0.74).setStroke()
            let pointRing = NSBezierPath(ovalIn: CGRect(x: point.x - 4, y: point.y - 4, width: 8, height: 8))
            pointRing.lineWidth = 1
            pointRing.stroke()

            drawFittedText(
                history[index].label,
                in: CGRect(x: point.x - 22, y: baseline + 8, width: 44, height: 16),
                font: .systemFont(ofSize: 10, weight: .bold),
                color: mutedTextColor,
                alignment: .center
            )
        }

        if let hoveredTrendIndex,
           history.indices.contains(hoveredTrendIndex) {
            drawTrendTooltip(
                for: history[hoveredTrendIndex],
                at: points[hoveredTrendIndex],
                in: rect
            )
        }
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
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.32)
        shadow.shadowBlurRadius = 12
        shadow.shadowOffset = CGSize(width: 0, height: 4)
        shadow.set()
        NSColor(calibratedRed: 0.08, green: 0.10, blue: 0.13, alpha: 0.94).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()

        borderColor.withAlphaComponent(0.56).setStroke()
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

    private func drawInfoCard(title: String, value: String, in rect: CGRect, tint: NSColor?, titleWidth: CGFloat = 190) {
        drawGlassPanel(rect, radius: 26, highlighted: false, tint: tint)
        drawFittedText(
            title,
            in: CGRect(x: rect.minX + 26, y: rect.minY + 22, width: titleWidth, height: 28),
            font: .systemFont(ofSize: 24, weight: .heavy),
            color: mutedTextColor,
            alignment: .left
        )
        drawFittedText(
            value,
            in: CGRect(
                x: rect.minX + 24 + (title == "计划" ? 74 : 0),
                y: rect.minY + (title == "计划" ? 23 : 58),
                width: rect.width - 48 - (title == "计划" ? 74 : 0),
                height: title == "计划" ? 34 : 36
            ),
            font: .systemFont(ofSize: title == "计划" ? 30 : 26, weight: .heavy),
            color: textColor,
            alignment: .left
        )
    }

    private func drawGlassPanel(_ rect: CGRect, radius: CGFloat, highlighted: Bool, tint: NSColor? = nil) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        (highlighted ? hotGlassFill : glassFill).setFill()
        path.fill()

        if let tint {
            tint.withAlphaComponent(highlighted ? 0.18 : 0.12).setFill()
            path.fill()
        }

        let stroke = tint?.withAlphaComponent(0.40) ?? (highlighted ? hotBorderColor : borderColor)
        stroke.setStroke()
        path.lineWidth = highlighted ? 2.0 : 1.5
        path.stroke()

        let shine = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: radius - 2, yRadius: radius - 2)
        NSColor.white.withAlphaComponent(highlighted ? 0.05 : 0.03).setStroke()
        shine.lineWidth = 1
        shine.stroke()
    }

    private func drawStatusLight(in rect: CGRect, color: NSColor) {
        let pulse = (sin(animationPhase * 2.2) + 1) / 2
        color.withAlphaComponent(0.12 + pulse * 0.10).setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: -5 - pulse * 5, dy: -5 - pulse * 5)).fill()

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = color.withAlphaComponent(0.48 + pulse * 0.18)
        shadow.shadowBlurRadius = 8 + pulse * 7
        shadow.shadowOffset = .zero
        shadow.set()

        color.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 7, dy: 7)).fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.55).setStroke()
        let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 7, dy: 7))
        ring.lineWidth = 1.6
        ring.stroke()
    }

    private func drawMeter(in rect: CGRect, remainingPercent: Double?, color: NSColor) {
        let progress = CGFloat(max(0, min((remainingPercent ?? 0) / 100, 1)))
        let circle = NSBezierPath(ovalIn: rect)

        let bgGradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.24, green: 0.30, blue: 0.36, alpha: 0.82),
            NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.11, alpha: 0.90)
        ])
        bgGradient?.draw(in: circle, angle: -42)

        NSGraphicsContext.saveGraphicsState()
        circle.addClip()

        let fillHeight = max(progress * rect.height, progress > 0 ? 9 : 0)
        let fillRect = CGRect(x: rect.minX, y: rect.maxY - fillHeight, width: rect.width, height: fillHeight)
        color.withAlphaComponent(0.78).setFill()
        fillRect.fill()

        let wave = NSBezierPath()
        let baseY = rect.maxY - fillHeight + 4
        wave.move(to: CGPoint(x: rect.minX, y: baseY))
        for step in 0...28 {
            let x = rect.minX + rect.width * CGFloat(step) / 28
            let y = baseY + sin(CGFloat(step) / 28 * CGFloat.pi * 3.2 + animationPhase * 2.7) * 10
            wave.line(to: CGPoint(x: x, y: y))
        }
        wave.line(to: CGPoint(x: rect.maxX, y: rect.maxY))
        wave.line(to: CGPoint(x: rect.minX, y: rect.maxY))
        wave.close()
        color.withAlphaComponent(0.95).setFill()
        wave.fill()
        NSGraphicsContext.restoreGraphicsState()

        let rim = NSBezierPath(ovalIn: rect)
        borderColor.withAlphaComponent(0.86).setStroke()
        rim.lineWidth = 2.2
        rim.stroke()

        NSGraphicsContext.saveGraphicsState()
        circle.addClip()
        NSColor.white.withAlphaComponent(0.25).setFill()
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
            color: textColor,
            alignment: .center
        )
        drawFittedText(
            "剩余",
            in: CGRect(x: rect.minX + 64, y: rect.midY + 24, width: rect.width - 128, height: 30),
            font: .systemFont(ofSize: 24, weight: .heavy),
            color: textColor,
            alignment: .center
        )
    }

    private func drawIconButton(in rect: CGRect, kind: IconKind, spinning: Bool) {
        if kind == .close {
            drawCloseButtonBackground(in: rect)
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

    private func drawSystemSymbol(_ symbolName: String, in rect: CGRect, spinning: Bool) -> Bool {
        guard let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else {
            return false
        }

        let pointSize = rect.width * 0.44
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let configuredImage = image.withSymbolConfiguration(configuration) ?? image
        let tintedImage = tintedSymbolImage(configuredImage, color: textColor.withAlphaComponent(0.92))
        let side = rect.width * 0.46
        let drawRect = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)

        NSGraphicsContext.saveGraphicsState()
        if spinning {
            let transform = NSAffineTransform()
            transform.translateX(by: rect.midX, yBy: rect.midY)
            transform.rotate(byDegrees: -Double(animationPhase * 220))
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

    private func resetDescription(_ date: Date?) -> String {
        guard let date else { return "--" }
        let totalMinutes = max(0, Int(date.timeIntervalSinceNow / 60))
        if totalMinutes == 0 {
            return "即将重置"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return "\(hours)小时\(minutes)分钟后"
        }
        return "\(minutes)分钟后"
    }

    private func remainingDuration(_ date: Date?) -> String {
        guard let date else { return "--" }
        let totalMinutes = max(0, Int(date.timeIntervalSinceNow / 60))
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60

        if days > 0 {
            return "\(days)天\(hours)小时"
        }
        if hours > 0 {
            return "\(hours)小时\(minutes)分钟"
        }
        return "\(minutes)分钟"
    }

    private func startAnimation() {
        guard animationTimer == nil else { return }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.window?.isVisible == true else { return }
            self.animationPhase += 1.0 / 30.0
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
    case minus
    case close
}

private struct TrendHoverRegion {
    let index: Int
    let rect: CGRect
}
