import SwiftUI

struct ProjectsView: View {
    @ObservedObject var store: AppStore
    @State private var searchText = ""
    @State private var selectedProjectID: String?

    private var filteredProjects: [DashboardProject] {
        guard !searchText.isEmpty else { return store.usage.projects }
        return store.usage.projects.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.models.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
        }
    }

    private var selectedProject: DashboardProject? {
        let requested = selectedProjectID.flatMap { id in
            filteredProjects.first(where: { $0.id == id })
        }
        return requested ?? filteredProjects.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("项目")
                        .font(.system(size: 30, weight: .bold))
                    Text("Token、会话和活跃时长均来自本地 Codex 记录")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                summaryBadge("\(store.usage.projects.count)", label: "项目")
                summaryBadge(PulseFormatters.tokens(store.usage.tokens), label: "Tokens")
                summaryBadge(PulseFormatters.duration(store.usage.activeDuration), label: "活跃")
            }

            HStack(alignment: .top, spacing: 12) {
                PulsePanel {
                    VStack(spacing: 0) {
                        projectHeader
                        Divider().opacity(0.5)

                        if filteredProjects.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                LazyVStack(spacing: 0) {
                                    ForEach(filteredProjects) { project in
                                        projectButton(project)
                                        Divider().opacity(0.35).padding(.leading, 18)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                ProjectInspector(project: selectedProject)
                    .frame(width: 330)
            }
        }
        .padding(22)
        .background(PulseTheme.detailBackground)
        .searchable(text: $searchText, prompt: "搜索项目或模型")
    }

    private var projectHeader: some View {
        HStack {
            Text("名称")
            Spacer()
            Text("模型")
                .frame(width: 150, alignment: .leading)
            Text("活跃时长")
                .frame(width: 100, alignment: .trailing)
            Text("会话")
                .frame(width: 54, alignment: .trailing)
            Text("Tokens")
                .frame(width: 90, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(16)
    }

    private func projectButton(_ project: DashboardProject) -> some View {
        Button {
            selectedProjectID = project.id
        } label: {
            HStack(spacing: 10) {
                Image(systemName: project.isActive ? "terminal.fill" : "folder")
                    .foregroundStyle(project.isActive ? PulseTheme.mint : .secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)
                    if let lastActiveAt = project.lastActiveAt {
                        Text("更新于 \(PulseFormatters.relative(lastActiveAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(project.models.first ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
                Text(PulseFormatters.duration(project.activeDuration))
                    .font(.caption.monospacedDigit())
                    .frame(width: 100, alignment: .trailing)
                Text(project.sessions.formatted())
                    .font(.caption.monospacedDigit())
                    .frame(width: 54, alignment: .trailing)
                Text(PulseFormatters.tokens(project.tokens))
                    .font(.caption.monospacedDigit())
                    .frame(width: 90, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                selectedProject?.id == project.id ? Color.accentColor.opacity(0.14) : Color.clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("project.\(project.name)")
    }

    private func summaryBadge(_ value: String, label: String) -> some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct ProjectInspector: View {
    let project: DashboardProject?

    var body: some View {
        PulsePanel {
            if let project {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(PulseTheme.mint)
                        Text(project.name)
                            .font(.title3.weight(.semibold))
                            .lineLimit(1)
                        Spacer()
                        if project.isActive {
                            LiveStatusLabel(isLive: true, title: "活跃")
                        }
                    }

                    Divider()

                    inspectorMetric("Tokens", PulseFormatters.tokens(project.tokens), icon: "number")
                    inspectorMetric("活跃时长", PulseFormatters.duration(project.activeDuration), icon: "clock")
                    inspectorMetric("会话", project.sessions.formatted(), icon: "text.bubble")

                    Divider()

                    Text("Token 构成")
                        .font(.headline)
                    TokenBreakdownBar(project: project)

                    if !project.models.isEmpty {
                        Text("使用模型")
                            .font(.headline)
                        FlowLayout(spacing: 6) {
                            ForEach(project.models, id: \.self) { model in
                                Text(model)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(PulseTheme.panelHighlight, in: Capsule())
                            }
                        }
                    }

                    Spacer()
                }
                .padding(18)
            } else {
                ContentUnavailableView("选择一个项目", systemImage: "folder")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func inspectorMetric(_ title: String, _ value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
        }
    }
}

private struct TokenBreakdownBar: View {
    let project: DashboardProject

    private var parts: [(String, Int, Color)] {
        [
            ("输入", project.inputTokens, PulseTheme.cyan),
            ("缓存命中", project.cachedTokens, PulseTheme.violet),
            ("输出", project.outputTokens, PulseTheme.mint),
            ("推理", project.reasoningTokens, PulseTheme.amber)
        ]
    }

    private var total: Int { max(parts.reduce(0) { $0 + $1.1 }, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.0) { part in
                        Rectangle()
                            .fill(part.2)
                            .frame(width: max(2, proxy.size.width * Double(part.1) / Double(total)))
                    }
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)

            ForEach(parts, id: \.0) { part in
                HStack {
                    Circle().fill(part.2).frame(width: 7, height: 7)
                    Text(part.0).foregroundStyle(.secondary)
                    Spacer()
                    Text(PulseFormatters.tokens(part.1)).monospacedDigit()
                }
                .font(.caption)
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

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
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
