import SwiftUI
import TunnelServices

struct HistoryTaskView: View {
    @Bindable var nav: NavigationState

    @State private var tasks: [CaptureTask] = []

    var body: some View {
        Group {
            if tasks.isEmpty {
                ContentUnavailableView(
                    "暂无历史任务",
                    systemImage: "clock",
                    description: Text("完成抓包后会在此显示历史记录")
                )
            } else {
                List {
                    ForEach(tasks, id: \.id) { task in
                        HistoryTaskCell(task: task) {
                            if let taskId = task.id {
                                nav.navigate(to: .flowList(taskId: taskId.stringValue))
                            }
                        }
                    }
                    .onDelete(perform: deleteTasks)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("历史任务")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                #if os(iOS)
                EditButton()
                #else
                Button("编辑") { }
                #endif
            }
        }
        .onAppear {
            loadTasks()
        }
    }

    private func loadTasks() {
        tasks = CaptureTask.findAll(pageSize: 999, pageIndex: 0, orderBy: "id")
    }

    private func deleteTasks(at offsets: IndexSet) {
        let idsToDelete = offsets.compactMap { tasks[$0].id?.intValue }
        if !idsToDelete.isEmpty {
            _ = CaptureTask.deleteAll(taskIds: idsToDelete)
        }
        tasks.remove(atOffsets: offsets)
    }
}
