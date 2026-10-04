import SwiftUI
import AppKit
import UniformTypeIdentifiers
import CloneCore

struct WizardView: View {
    @Bindable var store: AppStore
    let record: CloneRecord?
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var source: URL?
    @State private var info: AppInfo?
    @State private var recipe: Recipe?
    @State private var name = ""
    @State private var displayName = ""
    @State private var language = "system"
    @State private var icon: URL?
    @State private var destination = ""
    @State private var dataDirectory = ""
    @State private var proxy = ProxySettings()
    @State private var password = ""
    @State private var injection: Injection = .auto
    @State private var issue: String?
    @State private var submitting = false
    private let stages = ["Chọn ứng dụng", "Cách nhân bản", "Tên và biểu tượng", "Mạng và lưu trữ", "Xác nhận"]
    private var windowHeight: CGFloat {
        switch step {
        case 0: return info == nil ? 320 : 420
        case 1: return 430
        case 2: return 510
        case 3: return proxy.enabled ? 620 : 440
        default: return 480
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 6) { Text(record == nil ? "Tạo bản sao ứng dụng" : "Sửa bản sao").font(.title2.bold()); Text("\(step + 1) / 5  ·  \(stages[step])").foregroundStyle(.secondary) }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary) }.buttonStyle(.plain).disabled(submitting)
            }.padding(24)
            HStack(spacing: 6) { ForEach(0..<5) { index in Capsule().fill(index <= step ? Color.accentColor : Color.secondary.opacity(0.18)).frame(height: 4) } }.padding(.horizontal, 24)
            Form {
                switch step {
                case 0: sourceForm
                case 1: strategyForm
                case 2: identityForm
                case 3: networkForm
                default: summaryForm
                }
            }.formStyle(.grouped)
            if let issue { Text(issue).font(.callout).foregroundStyle(.red).textSelection(.enabled).padding(.horizontal, 24) }
            if submitting { HStack { ProgressView().controlSize(.small); Text(store.progress).font(.callout) }.padding() }
            Divider()
            HStack {
                Button("Huỷ") { dismiss() }.disabled(submitting)
                Spacer()
                if step > (record == nil ? 0 : 2) { Button("Quay lại") { step -= 1 }.disabled(submitting) }
                Button(step == 4 ? (record == nil ? "Tạo bản sao" : "Lưu và cập nhật") : "Tiếp tục") { advance() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(submitting || (step == 0 && info == nil))
            }.padding(20)
        }.frame(width: 600, height: windowHeight).interactiveDismissDisabled(submitting).onAppear { restore() }
    }
    private var sourceForm: some View {
        Section {
            HStack(spacing: 18) {
                Image(nsImage: source.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: "app.dashed", accessibilityDescription: "Chọn ứng dụng")!).resizable().frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 8) { Text(info?.name ?? "Chọn ứng dụng cần nhân bản").font(.title3.bold()); Text(source?.path ?? "Hỗ trợ ứng dụng macOS dạng .app").font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                Spacer()
                Button("Chọn…") { selectSource() }
            }.padding(.vertical, 12)
            if let info { LabeledContent("Bundle ID", value: info.bundleID); LabeledContent("Phiên bản", value: info.version); LabeledContent("Loại nhận diện", value: info.type) }
        }
    }
    private var strategyForm: some View {
        Section("Quy tắc khớp: \(recipe?.appName ?? "Tự động nhận diện")") {
            Picker("Cách nhân bản", selection: Binding(get: { recipe?.strategy ?? .hard }, set: { recipe?.strategy = $0 })) { ForEach(Strategy.allCases, id: \.self) { Text($0.label).tag($0) } }
            Text("Bản sao cứng chép toàn bộ ứng dụng, đặt được tên riêng cho tiến trình chính và tiến trình phụ. Bản sao mềm chạy thẳng ứng dụng gốc, hợp với ứng dụng hỗ trợ thư mục cấu hình riêng.").font(.callout).foregroundStyle(.secondary)
            Picker("Cách chèn môi trường", selection: $injection) { Text("Tự động chọn").tag(Injection.auto); Text("Thư viện động trong tiến trình").tag(Injection.dylib); Text("Trình khởi chạy gốc").tag(Injection.launcher) }.disabled(recipe?.strategy == .soft)
            Toggle("Gỡ giới hạn sandbox của ứng dụng", isOn: Binding(get: { recipe?.stripSandbox ?? false }, set: { recipe?.stripSandbox = $0 }))
        }
    }
    private var identityForm: some View {
        Group {
            Section("Danh tính bản sao") {
                TextField("Tên bản sao / tên tiến trình", text: $name).disabled(record != nil)
                TextField("Tên hiển thị", text: $displayName)
                Picker("Ngôn ngữ giao diện", selection: $language) { ForEach(supportedLanguages, id: \.self) { Text($0 == "system" ? "Theo hệ thống" : Locale(identifier: "vi").localizedString(forIdentifier: $0) ?? $0).tag($0) } }
            }
            Section("Biểu tượng ứng dụng") {
                HStack(spacing: 18) {
                    Image(nsImage: previewIcon).resizable().frame(width: 76, height: 76)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(icon?.lastPathComponent ?? (record == nil ? "Dùng biểu tượng của ứng dụng gốc" : "Giữ biểu tượng hiện tại")).font(.callout)
                        HStack { Button("Chọn .icns…") { chooseIcon() }; Button("Khôi phục mặc định") { icon = nil } }
                    }
                }.padding(.vertical, 8)
                Text("Biểu tượng được chép vào bản sao và tự giữ lại khi sửa cài đặt hoặc cập nhật.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var networkForm: some View {
        Group {
            Section("Mạng riêng") {
                Toggle("Bật proxy", isOn: $proxy.enabled)
                if proxy.enabled {
                    Picker("Loại", selection: $proxy.type) { ForEach(["http", "https", "socks5"], id: \.self) { Text($0.uppercased()).tag($0) } }
                    TextField("Máy chủ", text: $proxy.host)
                    TextField("Cổng", value: $proxy.port, format: .number.grouping(.never))
                    TextField("Tên đăng nhập (tuỳ chọn)", text: $proxy.username)
                    SecureField("Mật khẩu (lưu vào Keychain)", text: $password)
                    TextField("Không qua proxy", text: $proxy.noProxy)
                    Text("Ứng dụng phải hỗ trợ biến môi trường proxy; hãy kiểm tra trong ứng dụng proxy xem kết nối có thực sự đi qua proxy không.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Vị trí lưu trữ") {
                TextField("Ứng dụng bản sao", text: $destination).disabled(record != nil)
                TextField("Dữ liệu riêng", text: $dataDirectory).disabled(record != nil)
                Text("Mặc định lưu trong thư mục người dùng, không cần quyền quản trị. Cập nhật vẫn giữ dữ liệu.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var summaryForm: some View {
        Section("Sắp \(record == nil ? "tạo" : "cập nhật")") {
            LabeledContent("Ứng dụng", value: info?.name ?? recipe?.appName ?? "")
            LabeledContent("Bản sao", value: name)
            LabeledContent("Cách nhân bản", value: recipe?.strategy.label ?? "")
            LabeledContent("Ngôn ngữ", value: language)
            LabeledContent("Mạng", value: proxy.enabled ? "\(proxy.type)://\(proxy.host):\(proxy.port)" : "Mạng hệ thống")
            Text(destination).font(.caption).textSelection(.enabled)
            if recipe?.strategy == .hard {
                Text("Tiến trình chính: \(name)\nTiến trình phụ: \(name)-<tên gốc>").font(.system(.callout, design: .monospaced))
            }
        }
    }
    private var previewIcon: NSImage {
        if let icon, let image = NSImage(contentsOf: icon) { return image }
        if let url = record?.configuration.destination ?? source { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "app", accessibilityDescription: "Biểu tượng ứng dụng")!
    }
    private func selectSource() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]; panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let inspected = try Inspector.inspect(url); source = url; info = inspected
            let r = Recipes.match(inspected, recipes: store.recipes); recipe = r; injection = r.injection
            name = inspected.name + " 2"; displayName = name; icon = nil
            destination = store.root.appendingPathComponent("Apps/\(name).app").path
            dataDirectory = store.root.appendingPathComponent("Data/\(name)").path; issue = nil
        } catch { issue = error.localizedDescription }
    }
    private func chooseIcon() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "icns")!]
        if panel.runModal() == .OK { icon = panel.url }
    }
    private func configuration() throws -> CloneConfiguration {
        guard let source, let recipe else { throw CloneFailure.invalid("Hãy chọn ứng dụng") }
        var c = record?.configuration ?? CloneConfiguration(source: source, name: name, destination: URL(fileURLWithPath: destination), dataDirectory: URL(fileURLWithPath: dataDirectory), recipe: recipe)
        c.name = name; c.displayName = displayName.isEmpty ? name : displayName; c.recipe = recipe
        c.destination = URL(fileURLWithPath: NSString(string: destination).expandingTildeInPath)
        c.dataDirectory = URL(fileURLWithPath: NSString(string: dataDirectory).expandingTildeInPath)
        c.proxy = proxy; c.language = language; c.customIcon = icon; c.injection = injection
        try c.validate(); return c
    }
    private func advance() {
        issue = nil
        do {
            if step == 2 {
                try validateName(name)
                if record == nil { destination = store.root.appendingPathComponent("Apps/\(name).app").path; dataDirectory = store.root.appendingPathComponent("Data/\(name)").path }
            }
            if step >= 3 { _ = try configuration() }
            if step < 4 { step += 1; return }
            let config = try configuration(); submitting = true
            Task { let success = await store.build(config, password: password, updating: record != nil); submitting = false; if success { dismiss() } else { issue = store.error; store.error = nil } }
        } catch { issue = error.localizedDescription }
    }
    private func restore() {
        guard let record else { return }
        let c = record.configuration; source = c.source; info = try? Inspector.inspect(c.source); recipe = c.recipe
        name = c.name; displayName = c.displayName; language = c.language; proxy = c.proxy; injection = c.injection
        destination = c.destination.path; dataDirectory = c.dataDirectory.path; step = 2
        do { password = try Secrets.read(c.id) } catch { issue = error.localizedDescription }
    }
}
