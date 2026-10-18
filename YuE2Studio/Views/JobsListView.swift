import SwiftUI

/// 任务列表：服务器任务 + 本地历史兜底。
struct JobsListView: View {
    @ObservedObject var vm: JobsViewModel

    var body: some View {
        NavigationStack {
            List {
                if let error = vm.errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                if vm.isLoading && vm.items.isEmpty {
                    Section {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    }
                }
                Section {
                    ForEach(vm.items) { item in
                        NavigationLink(value: item.id) {
                            JobRowView(item: item)
                        }
                        .swipeActions {
                            if item.status.isActive && !item.missing {
                                Button("取消", role: .destructive) { vm.cancel(id: item.id) }
                            }
                        }
                    }
                } header: {
                    Text(vm.hasActive ? "创作进行中（自动刷新）" : "全部任务")
                }
            }
            .navigationDestination(for: String.self) { jobId in
                JobDetailView(vm: JobDetailShell.vm(jobId: jobId))
            }
            .navigationTitle("任务")
            .refreshable { await vm.refresh() }
            .task {
                await vm.refresh()
                vm.startPolling()
            }
            .onDisappear { vm.stopPolling() }
        }
    }
}

struct JobRowView: View {
    let item: JobListItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.color(for: phaseColorKey).opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .foregroundStyle(Theme.color(for: phaseColorKey))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Pill(text: item.cot.title, color: Theme.accent)
                    Text(item.status.label + (item.missing ? " · 已失效" : ""))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Formatters.displayDate(item.createdAt))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let seconds = item.audioSeconds {
                    Text(Formatters.duration(seconds))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var phaseColorKey: String {
        switch item.status {
        case .succeeded: return "done"
        case .failed: return "failed"
        case .cancelled: return "queued"
        case .queued: return "queued"
        case .running: return "synthesizing"
        }
    }

    private var icon: String {
        if item.missing { return "questionmark.circle" }
        switch item.status {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle"
        case .queued: return "clock"
        case .running: return "waveform"
        }
    }
}

#Preview {
    JobsListView(vm: JobsViewModel(clientProvider: { DeadClient() },
                                   history: HistoryStore(directoryURL: FileManager.default.temporaryDirectory)))
}
