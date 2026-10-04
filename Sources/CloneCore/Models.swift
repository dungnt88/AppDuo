import Foundation

public enum CloneFailure: LocalizedError {
    case invalid(String), command(String)
    public var errorDescription: String? { switch self { case .invalid(let s), .command(let s): return s } }
}
public enum Strategy: String, Codable, CaseIterable, Sendable {
    case hard = "hard_clone", soft = "soft_clone"
    public var label: String { self == .hard ? "Bản sao cứng · Ứng dụng độc lập" : "Bản sao mềm · Trình khởi chạy nhẹ" }
}
public enum Injection: String, Codable, CaseIterable, Sendable { case auto, dylib, launcher }
public struct ProxySettings: Codable, Sendable, Equatable {
    public var enabled = false
    public var type = "http"
    public var host = "127.0.0.1"
    public var port = 7890
    public var username = ""
    public var noProxy = "localhost,127.0.0.1,*.local"
    public init() {}
    public func url(password: String = "") throws -> String {
        guard ["http", "https", "socks5"].contains(type), (1...65535).contains(port), !host.isEmpty,
              !host.contains(where: { $0.isWhitespace || "/@?#".contains($0) }) else { throw CloneFailure.invalid("Địa chỉ hoặc cổng proxy không hợp lệ") }
        var c = URLComponents(); c.scheme = type; c.host = host; c.port = port
        if !username.isEmpty { c.user = username; c.password = password.isEmpty ? nil : password }
        guard let url = c.url else { throw CloneFailure.invalid("Không tạo được địa chỉ proxy") }; return url.absoluteString
    }
}
public struct Recipe: Identifiable, Codable, Sendable {
    public var bundleID: String
    public var appName: String
    public var strategy: Strategy
    public var stripSandbox = false
    public var environment: [String: String] = [:]
    public var symlinks: [String] = []
    public var arguments: [String] = []
    public var appType = "generic"
    public var singleton = false
    public var cef = false
    public var lark = false
    public var chatgpt = false
    public var stripURLs = false
    public var injection: Injection = .auto
    public var id: String { bundleID }
    public init(bundleID: String, appName: String, strategy: Strategy = .hard) {
        self.bundleID = bundleID; self.appName = appName; self.strategy = strategy
    }
}
public struct AppInfo: Sendable {
    public let url: URL
    public let bundleID: String
    public let name: String
    public let executable: String
    public let version: String
    public let type: String
    public init(url: URL, bundleID: String, name: String, executable: String, version: String = "", type: String = "generic") {
        self.url = url; self.bundleID = bundleID; self.name = name; self.executable = executable; self.version = version; self.type = type
    }
}
public struct CloneConfiguration: Codable, Sendable, Identifiable {
    public var id = UUID()
    public var source: URL
    public var name: String
    public var displayName: String
    public var destination: URL
    public var dataDirectory: URL
    public var bundleID: String
    public var recipe: Recipe
    public var language = "system"
    public var proxy = ProxySettings()
    public var injection: Injection = .auto
    public var customIcon: URL?
    public init(source: URL, name: String, destination: URL, dataDirectory: URL, recipe: Recipe) {
        self.source = source; self.name = name; self.displayName = name; self.destination = destination
        self.dataDirectory = dataDirectory; self.recipe = recipe
        self.bundleID = recipe.bundleID + ".atbclone." + UUID().uuidString.lowercased()
    }
    public func validate() throws {
        try validateName(name)
        guard !displayName.contains("\0"), destination.pathExtension == "app",
              !bundleID.isEmpty, bundleID.range(of: "^[A-Za-z0-9.-]+$", options: .regularExpression) != nil else { throw CloneFailure.invalid("Tên ứng dụng, đường dẫn hoặc Bundle ID không hợp lệ") }
        let src = source.resolvingSymlinksInPath().standardizedFileURL.path
        let dst = destination.resolvingSymlinksInPath().standardizedFileURL.path
        let data = dataDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        guard src != dst, !dst.hasPrefix(src + "/"), !src.hasPrefix(dst + "/"),
              !data.hasPrefix(dst + "/"), !dst.hasPrefix(data + "/"), data != dst,
              data != NSHomeDirectory(), data != "/", data != src, !data.hasPrefix(src + "/"), !src.hasPrefix(data + "/") else { throw CloneFailure.invalid("Ứng dụng gốc, bản sao và thư mục dữ liệu không được nằm lồng nhau") }
        if proxy.enabled { _ = try proxy.url() }
        for key in recipe.environment.keys {
            guard key.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil else { throw CloneFailure.invalid("Biến môi trường không hợp lệ: \(key)") }
        }
        for path in recipe.symlinks {
            guard !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else { throw CloneFailure.invalid("Đường dẫn chia sẻ không hợp lệ: \(path)") }
        }
    }
}
public struct CloneRecord: Codable, Identifiable, Sendable {
    public var configuration: CloneConfiguration
    public var createdAt = Date()
    public var updatedAt = Date()
    public var id: UUID { configuration.id }
    public init(configuration: CloneConfiguration) { self.configuration = configuration }
}
public func validateName(_ name: String) throws {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name != ".", name != "..",
          name.utf8.count < 160, !name.contains(where: { $0 == "/" || $0 == ":" || $0.isNewline || $0.asciiValue == 0 }) else { throw CloneFailure.invalid("Tên không được để trống, không chứa /, : hoặc xuống dòng, và không quá dài") }
}
public enum Assets {
    // Older SwiftPM accessors skip Contents/Resources inside a .app and fatalError on other machines.
    public static let root: URL = {
        let packaged = Bundle.main.resourceURL.flatMap { Bundle(url: $0.appendingPathComponent("AppDuo_CloneCore.bundle")) }
        return (packaged ?? Bundle.module).url(forResource: "Resources", withExtension: nil)!
    }()
    public static let icon = root.appendingPathComponent("AppIcon.icns")
}
public let supportedLanguages = ["system", "vi", "zh-Hans", "zh-Hant", "en", "ja", "ko", "de", "fr", "es", "ru"]
