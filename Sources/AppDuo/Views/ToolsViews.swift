import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CloneCore

struct RecipesView: View {
    @Bindable var store: AppStore
    @State private var search = ""
    @State private var selected: String?
    @State private var editor = ""
    @State private var editing = false
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { Text("Thư viện quy tắc").font(.largeTitle.bold()); Spacer(); Button("Nhập YAML…") { importRecipe() } }.padding(24)
            Text("\(store.recipes.count) quy tắc · ưu tiên quy tắc cục bộ").foregroundStyle(.secondary).padding(.horizontal, 24)
            List(store.recipes.filter { search.isEmpty || $0.appName.localizedCaseInsensitiveContains(search) || $0.bundleID.localizedCaseInsensitiveContains(search) }, selection: $selected) { recipe in
                HStack {
                    Image(systemName: recipe.strategy == .hard ? "app.badge" : "link").foregroundStyle(.tint).frame(width: 28)
                    VStack(alignment: .leading, spacing: 5) { Text(recipe.appName).font(.headline); Text(recipe.bundleID).font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary) }
                    Spacer(); Text(recipe.strategy.label).font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 8).tag(recipe.id).contextMenu { Button("Sửa YAML…") { edit(recipe) } }
                .onTapGesture(count: 2) { edit(recipe) }
            }.listStyle(.inset)
        }.navigationTitle("Quy tắc").searchable(text: $search, prompt: "Tìm ứng dụng hoặc Bundle ID")
        .sheet(isPresented: $editing) {
            VStack(alignment: .leading) {
                Text("Sửa quy tắc ứng dụng").font(.title2.bold())
                Text("Lưu thành quy tắc cục bộ ghi đè; quy tắc có sẵn được giữ nguyên.").foregroundStyle(.secondary)
                TextEditor(text: $editor).font(.system(.body, design: .monospaced)).border(.quaternary)
                HStack { Button("Huỷ") { editing = false }; Spacer(); Button("Lưu") { saveRecipe(editor) }.buttonStyle(.borderedProminent) }
            }.padding(24).frame(width: 690, height: 600)
        }
    }
    private func edit(_ recipe: Recipe) {
        let custom = store.root.appendingPathComponent("recipes/\(recipe.bundleID).yaml")
        let builtin = Assets.root.appendingPathComponent("recipes/\(recipe.bundleID).yaml")
        do { editor = try String(contentsOf: FileManager.default.fileExists(atPath: custom.path) ? custom : builtin, encoding: .utf8); editing = true }
        catch { store.error = error.localizedDescription }
    }
    private func importRecipe() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "yaml") ?? .text, UTType(filenameExtension: "yml") ?? .text]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { editor = try String(contentsOf: url, encoding: .utf8); _ = try Recipes.decode(editor); editing = true } catch { store.error = error.localizedDescription }
    }
    private func saveRecipe(_ source: String) {
        do {
            let recipe = try Recipes.decode(source)
            guard recipe.bundleID.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil else { throw CloneFailure.invalid("Bundle ID không hợp lệ") }
            let folder = store.root.appendingPathComponent("recipes"); try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try source.write(to: folder.appendingPathComponent(recipe.bundleID + ".yaml"), atomically: true, encoding: .utf8)
            editing = false; Task { await store.reload() }
        } catch { store.error = error.localizedDescription }
    }
}
struct ProbeView: View {
    let store: AppStore
    @State private var info: AppInfo?
    @State private var recipe: Recipe?
    var body: some View {
        Form {
            Section {
                Text("Tìm hiểu cách nhân bản ứng dụng").font(.title.bold())
                Text("Đọc metadata và Frameworks của ứng dụng, đối chiếu với quy tắc có sẵn.").foregroundStyle(.secondary)
                Button("Chọn ứng dụng…") {
                    let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
                    if panel.runModal() == .OK, let url = panel.url {
                        do { let value = try Inspector.inspect(url); info = value; recipe = Recipes.match(value, recipes: store.recipes) }
                        catch { store.error = error.localizedDescription }
                    }
                }
            }
            if let info, let recipe {
                Section(info.name) {
                    LabeledContent("Bundle ID", value: info.bundleID)
                    LabeledContent("Phiên bản", value: info.version)
                    LabeledContent("Chương trình chính", value: info.executable)
                    LabeledContent("Loại kiến trúc", value: info.type)
                    LabeledContent("Cách đề xuất", value: recipe.strategy.label)
                    LabeledContent("Nguồn quy tắc", value: store.recipes.contains(where: { $0.bundleID == info.bundleID }) ? "Quy tắc có sẵn" : "Tự động nhận diện")
                    Text(info.url.path).font(.caption).textSelection(.enabled)
                }
            }
        }.formStyle(.grouped).navigationTitle("Phân tích ứng dụng")
    }
}
struct DoctorView: View {
    @State private var results: [(String, String, Bool)] = []
    @State private var running = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Kiểm tra môi trường").font(.largeTitle.bold())
            Text("Kiểm tra trình biên dịch, công cụ ký lại và môi trường macOS.").foregroundStyle(.secondary)
            Button("Bắt đầu kiểm tra") { run() }.buttonStyle(.borderedProminent).disabled(running)
            if running { ProgressView() }
            ForEach(results.indices, id: \.self) { i in
                HStack(alignment: .top) {
                    Image(systemName: results[i].2 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill").foregroundStyle(results[i].2 ? .green : .orange)
                    VStack(alignment: .leading, spacing: 6) { Text(results[i].0).font(.headline); Text(results[i].1).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                }.padding().frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
            Spacer()
        }.padding(30).navigationTitle("Kiểm tra môi trường")
    }
    private func run() {
        running = true
        Task {
            let checks = await Task.detached { () -> [(String, String, Bool)] in
                [("macOS", "/usr/bin/sw_vers", ["-productVersion"]), ("Trình biên dịch", "/usr/bin/xcrun", ["--find", "clang"]), ("Công cụ ký", "/usr/bin/xcrun", ["--find", "codesign"])].map { title, executable, args in
                    do { return (title, try Command.run(executable, args).trimmingCharacters(in: .whitespacesAndNewlines), true) }
                    catch { return (title, error.localizedDescription, false) }
                }
            }.value
            results = checks; running = false
        }
    }
}
struct LogsView: View {
    let store: AppStore
    var body: some View {
        ScrollView { Text(store.logs.isEmpty ? "Chưa có nhật ký thao tác" : store.logs.joined(separator: "\n")).font(.system(.callout, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(24) }.navigationTitle("Nhật ký thao tác")
    }
}
struct SettingsView: View {
    let root: URL
    var body: some View {
        Form {
            Section("AppDuo") { Text("Swift + SwiftUI thuần · macOS 14+"); Text("Dữ liệu của bản Swift được lưu riêng, tách khỏi bản gốc.").foregroundStyle(.secondary) }
            Section("Vị trí dữ liệu") { Text(root.path).textSelection(.enabled); Button("Mở trong Finder") { try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); NSWorkspace.shared.open(root) } }
        }.formStyle(.grouped).frame(width: 500, height: 300)
    }
}
