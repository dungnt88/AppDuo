import SwiftUI
import AppKit
import CloneCore

struct ContentView: View {
    @Bindable var store: AppStore
    @State private var query = ""
    @State private var removing: CloneRecord?
    var body: some View {
        NavigationStack {
            clones
            .toolbar {
                ToolbarItem { Button { Task { await store.reload() } } label: { Label("Làm mới", systemImage: "arrow.clockwise") }.disabled(store.busy) }
                ToolbarItem { Button { store.editing = nil; store.showingWizard = true } label: { Label("Tạo bản sao", systemImage: "plus") }.disabled(store.busy) }
            }
            .safeAreaInset(edge: .bottom) {
                if store.busy { HStack(spacing: 10) { ProgressView().controlSize(.small); Text(store.progress).font(.callout); Spacer() }.padding(12).background(.bar) }
            }
        }
        .sheet(isPresented: $store.showingWizard) { WizardView(store: store, record: store.editing) }
        .alert("Thao tác chưa hoàn tất", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
        .confirmationDialog("Chuyển bản sao vào Thùng rác?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let record = removing {
                Button("Xoá ứng dụng, giữ dữ liệu", role: .destructive) { Task { await store.remove(record, withData: false) } }
                Button("Xoá cả ứng dụng và dữ liệu", role: .destructive) { Task { await store.remove(record, withData: true) } }
            }
            Button("Huỷ", role: .cancel) {}
        } message: { Text("Mặc định giữ lại lịch sử trò chuyện và dữ liệu đăng nhập. Thư mục dữ liệu tuỳ chỉnh thì bạn tự quản lý.") }
    }
    private var clones: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mỗi danh tính, một không gian riêng.").font(.largeTitle.bold())
                        Text("Quản lý bản sao ứng dụng, dữ liệu riêng và cài đặt mạng.").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(store.records.count) bản sao").font(.callout).padding(.horizontal, 14).padding(.vertical, 8).background(.quaternary, in: Capsule())
                }
                if store.records.isEmpty {
                    ContentUnavailableView {
                        Label("Tạo bản sao đầu tiên", systemImage: "square.on.square.dashed")
                    } description: { Text("Chọn một ứng dụng để tách riêng không gian cho công việc và cuộc sống.") } actions: {
                        Button("Tạo bản sao") { store.editing = nil; store.showingWizard = true }.buttonStyle(.borderedProminent).disabled(store.busy)
                    }.frame(maxWidth: .infinity, minHeight: 340)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 250), spacing: 18, alignment: .leading)], alignment: .leading, spacing: 18) {
                        ForEach(store.records.filter { query.isEmpty || $0.configuration.name.localizedCaseInsensitiveContains(query) }) { record in
                            CloneCard(record: record, busy: store.busy, updateVersion: store.availableUpdates[record.id], launch: { store.launch(record) }, edit: { store.editing = record; store.showingWizard = true }, update: { Task { await store.update(record) } }, remove: { removing = record })
                        }
                    }
                }
            }.padding(30)
        }.navigationTitle("Bản sao ứng dụng").searchable(text: $query, prompt: "Tìm bản sao")
    }
}
struct CloneCard: View {
    let record: CloneRecord
    let busy: Bool
    let updateVersion: String?
    let launch: () -> Void, edit: () -> Void, update: () -> Void, remove: () -> Void
    var body: some View {
        let c = record.configuration
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: c.destination.path)).resizable().frame(width: 54, height: 54)
                    .overlay(alignment: .bottomTrailing) {
                        if let updateVersion {
                            Button(action: update) {
                                Image(systemName: "arrow.up.circle.fill").font(.system(size: 22, weight: .semibold))
                                    .symbolRenderingMode(.palette).foregroundStyle(.white, .blue)
                                    .padding(2).background(.background, in: Circle())
                            }.buttonStyle(.plain).disabled(busy)
                                .help("Nâng cấp lên \(updateVersion), giữ dữ liệu và cài đặt")
                                .accessibilityLabel("Nâng cấp \(c.displayName) lên \(updateVersion)")
                        }
                    }
                VStack(alignment: .leading, spacing: 5) { Text(c.displayName).font(.title3.bold()); Text(c.recipe.appName).font(.caption).foregroundStyle(.secondary) }
                Spacer()
                Menu { Button("Sửa cài đặt…", action: edit); Button("Cập nhật bản sao", action: update); Button("Hiện trong Finder") { NSWorkspace.shared.activateFileViewerSelecting([c.destination]) }; Divider(); Button("Xoá…", role: .destructive, action: remove) } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28).accessibilityLabel("Thao tác khác").help("Thao tác khác").disabled(busy)
            }
            HStack(spacing: 12) {
                Label(c.recipe.strategy == .hard ? "Bản sao cứng" : "Bản sao mềm", systemImage: "square.stack").font(.caption)
                Label(c.proxy.enabled ? "Proxy riêng" : "Mạng hệ thống", systemImage: c.proxy.enabled ? "network" : "globe").font(.caption)
            }.foregroundStyle(.secondary)
            Divider()
            HStack {
                Text(c.name).font(.system(.caption, design: .monospaced)).lineLimit(1)
                Spacer()
                if updateVersion != nil { Button("Nâng cấp", action: update).disabled(busy).help("Cập nhật bản sao theo phiên bản mới nhất của ứng dụng gốc trên máy") }
                Button("Mở", action: launch).buttonStyle(.borderedProminent).disabled(busy)
            }
        }.padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)).overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
    }
}
