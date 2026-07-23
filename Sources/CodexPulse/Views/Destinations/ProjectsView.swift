import SwiftUI

struct ProjectsView: View {
    @ObservedObject var store: AppStore
    @State private var searchText = ""
    @State private var selectedProjectID: DashboardProject.ID?

    private var filteredProjects: [DashboardProject] {
        guard !searchText.isEmpty else { return store.usage.projects }
        return store.usage.projects.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.models.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        }
    }

    private var selectedProject: DashboardProject? {
        selectedProjectID.flatMap { id in
            filteredProjects.first(where: { $0.id == id })
        }
    }

    private var visibleTokens: Int {
        filteredProjects.reduce(0) { $0 + $1.tokens }
    }

    private var visibleActiveDuration: TimeInterval {
        filteredProjects.reduce(0) { $0 + $1.activeDuration }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader
            Divider()

            GeometryReader { proxy in
                if proxy.size.width >= 860 {
                    HSplitView {
                        projectList
                            .frame(minWidth: 520)

                        ProjectInspector(project: selectedProject)
                            .frame(minWidth: 270, idealWidth: 320, maxWidth: 390)
                    }
                } else {
                    VStack(spacing: 0) {
                        projectList
                        Divider()
                        ProjectInspector(project: selectedProject, compact: true)
                            .frame(minHeight: 210, idealHeight: 250, maxHeight: 300)
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "搜索项目或模型")
        .onChange(of: filteredProjects.map(\.id), initial: true) { _, ids in
            if let selectedProjectID, ids.contains(selectedProjectID) { return }
            selectedProjectID = ids.first
        }
        .accessibilityIdentifier("projects.page")
    }

    private var pageHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text("项目")
                    .font(.title2.weight(.semibold))
                Text("本地 Codex 活动")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 24)

            summaryValue(filteredProjects.count.formatted(), label: "个项目")
            summaryDivider
            summaryValue(PulseFormatters.tokens(visibleTokens), label: "Tokens")
            summaryDivider
            summaryValue(PulseFormatters.duration(visibleActiveDuration), label: "活跃")
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private func summaryValue(_ value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var summaryDivider: some View {
        Circle()
            .fill(.tertiary)
            .frame(width: 3, height: 3)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var projectList: some View {
        if filteredProjects.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Table(filteredProjects, selection: $selectedProjectID) {
                TableColumn("项目") { project in
                    ProjectNameCell(project: project)
                        .accessibilityIdentifier("project.\(project.id)")
                }
                .width(min: 180, ideal: 260)

                TableColumn("模型") { project in
                    ProjectModelsCell(models: project.models)
                }
                .width(min: 120, ideal: 160, max: 220)

                TableColumn("活跃时长") { project in
                    Text(PulseFormatters.duration(project.activeDuration))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .width(min: 86, ideal: 104, max: 120)

                TableColumn("会话") { project in
                    Text(project.sessions.formatted())
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 50, ideal: 58, max: 68)

                TableColumn("Tokens") { project in
                    Text(PulseFormatters.tokens(project.tokens))
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 70, ideal: 82, max: 96)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: false))
            .accessibilityIdentifier("projects.table")
        }
    }
}

private struct ProjectNameCell: View {
    let project: DashboardProject

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: project.isActive ? "terminal.fill" : "folder")
                .foregroundStyle(project.isActive ? PulseTheme.mint : .secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let lastActiveAt = project.lastActiveAt {
                    Text(PulseFormatters.relative(lastActiveAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(project.name)
        .accessibilityValue(project.isActive ? "当前活跃" : "未活跃")
    }
}

private struct ProjectModelsCell: View {
    let models: [String]

    var body: some View {
        HStack(spacing: 5) {
            Text(models.first ?? "—")
                .lineLimit(1)
            if models.count > 1 {
                Text("+\(models.count - 1)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("模型")
        .accessibilityValue(models.isEmpty ? "无" : models.joined(separator: "、"))
    }
}

private struct ProjectInspector: View {
    let project: DashboardProject?
    var compact = false

    var body: some View {
        Group {
            if let project {
                ScrollView {
                    VStack(alignment: .leading, spacing: compact ? 14 : 20) {
                        identity(project)
                        Divider()
                        metrics(project)
                        Divider()
                        tokenSection(project)

                        if !project.models.isEmpty {
                            Divider()
                            modelsSection(project.models)
                        }
                    }
                    .padding(compact ? 16 : 20)
                }
            } else {
                ContentUnavailableView(
                    "选择一个项目",
                    systemImage: "folder",
                    description: Text("从列表中选择项目以查看用量明细")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.22))
        .accessibilityIdentifier("projects.inspector")
    }

    private func identity(_ project: DashboardProject) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: project.isActive ? "terminal.fill" : "folder.fill")
                    .foregroundStyle(project.isActive ? PulseTheme.mint : .secondary)
                Text(project.name)
                    .font(.title3.weight(.semibold))
                    .lineLimit(2)
                Spacer(minLength: 8)
            }

            HStack(spacing: 7) {
                Circle()
                    .fill(project.isActive ? PulseTheme.mint : Color.secondary.opacity(0.6))
                    .frame(width: 6, height: 6)
                Text(project.isActive ? "当前活跃" : lastActivity(project.lastActiveAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func metrics(_ project: DashboardProject) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 11) {
            metricRow("Tokens", PulseFormatters.tokens(project.tokens))
            metricRow("活跃时长", PulseFormatters.duration(project.activeDuration))
            metricRow("会话", project.sessions.formatted())
        }
    }

    private func metricRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private func tokenSection(_ project: DashboardProject) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Token 构成")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            TokenBreakdownBar(project: project)
        }
    }

    private func modelsSection(_ models: [String]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("使用模型")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 6) {
                ForEach(models, id: \.self) { model in
                    Text(model)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                }
            }
        }
    }

    private func lastActivity(_ date: Date?) -> String {
        guard let date else { return "暂无活动时间" }
        return "上次活跃 \(PulseFormatters.relative(date))"
    }
}

private struct TokenBreakdownBar: View {
    private struct Part: Identifiable {
        let title: String
        let value: Int
        let color: Color
        var id: String { title }
    }

    let project: DashboardProject

    private var parts: [Part] {
        [
            Part(
                title: "输入",
                value: max(0, project.inputTokens - project.cachedTokens),
                color: PulseTheme.cyan
            ),
            Part(title: "缓存命中", value: project.cachedTokens, color: PulseTheme.violet),
            Part(
                title: "输出",
                value: max(0, project.outputTokens - project.reasoningTokens),
                color: PulseTheme.mint
            ),
            Part(title: "推理", value: project.reasoningTokens, color: PulseTheme.amber)
        ]
    }

    private var positiveParts: [Part] {
        parts.filter { $0.value > 0 }
    }

    private var total: Int {
        positiveParts.reduce(0) { $0 + $1.value }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)

                    if total > 0 {
                        let spacing = CGFloat(max(positiveParts.count - 1, 0))
                        let usableWidth = max(proxy.size.width - spacing, 0)

                        HStack(spacing: 1) {
                            ForEach(positiveParts) { part in
                                Rectangle()
                                    .fill(part.color)
                                    .frame(
                                        width: usableWidth * CGFloat(part.value) / CGFloat(total)
                                    )
                            }
                        }
                        .clipShape(Capsule())
                    }
                }
            }
            .frame(height: 7)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Token 构成")
            .accessibilityValue(parts.map { "\($0.title) \(PulseFormatters.tokens($0.value))" }.joined(separator: "，"))

            ForEach(parts) { part in
                HStack(spacing: 7) {
                    Circle()
                        .fill(part.color)
                        .frame(width: 6, height: 6)
                    Text(part.title)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(PulseFormatters.tokens(part.value))
                        .monospacedDigit()
                }
                .font(.caption)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width.isFinite ? width : x, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
