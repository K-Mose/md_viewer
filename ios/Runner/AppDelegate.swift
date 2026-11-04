import Flutter
import UIKit
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    DocumentsBridge.shared.register(with: engineBridge.pluginRegistry)
  }
}

/// 문서 선택(UIDocumentPicker, 원본 위치에서 열기)과 security-scoped bookmark로 다시 열기,
/// 외부 앱 "연결 프로그램"으로 열린 파일 전달을 담당한다.
///
/// 새 Swift 파일을 만들면 Xcode 프로젝트(pbxproj)에 등록해야 해서 AppDelegate.swift 안에 둔다.
final class DocumentsBridge: NSObject, UIDocumentPickerDelegate {
  static let shared = DocumentsBridge()

  private var openedFileChannel: FlutterMethodChannel?
  private var pendingPick: FlutterResult?
  /// 새 파일 저장(내보내기) 대기: 결과 콜백과 정리할 임시 폴더
  private var pendingExport: (FlutterResult, URL)?
  private weak var exportPicker: UIDocumentPickerViewController?
  /// Dart가 getInitialFile을 호출하기 전에 도착한 파일 (콜드 스타트)
  private var pendingFiles: [[String: Any]] = []
  private var dartListening = false
  private let queue = DispatchQueue(label: "md_viewer.documents", qos: .userInitiated)

  func register(with registry: FlutterPluginRegistry) {
    guard let registrar = registry.registrar(forPlugin: "MdViewerDocuments") else { return }
    let messenger = registrar.messenger()

    let documents = FlutterMethodChannel(name: "md_viewer/documents", binaryMessenger: messenger)
    documents.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "pickDocument":
        self.pickDocument(result: result)
      case "readDocument":
        guard let value = args?["value"] as? String, let data = Data(base64Encoded: value) else {
          result(FlutterError(code: "invalid_argument", message: "bookmark가 없습니다", details: nil))
          return
        }
        self.runIo(result) { try self.readBookmark(data) }
      case "createDocument":
        guard let name = args?["name"] as? String,
          let bytes = args?["bytes"] as? FlutterStandardTypedData
        else {
          result(FlutterError(code: "invalid_argument", message: "name/bytes가 없습니다", details: nil))
          return
        }
        self.createDocument(name: name, data: bytes.data, result: result)
      case "writeDocument":
        guard let value = args?["value"] as? String, let bookmark = Data(base64Encoded: value),
          let bytes = args?["bytes"] as? FlutterStandardTypedData
        else {
          result(FlutterError(code: "invalid_argument", message: "bookmark/bytes가 없습니다", details: nil))
          return
        }
        self.runIo(result) { try self.writeBookmark(bookmark, data: bytes.data) }
      case "releaseDocument":
        result(nil)  // iOS 북마크는 따로 해제할 권한이 없다.
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let opened = FlutterMethodChannel(name: "md_viewer/opened_file", binaryMessenger: messenger)
    opened.setMethodCallHandler { [weak self] call, result in
      guard let self = self, call.method == "getInitialFile" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.dartListening = true
      let files = self.pendingFiles
      self.pendingFiles.removeAll()
      result(files.first)
      for file in files.dropFirst() {
        self.openedFileChannel?.invokeMethod("fileOpened", arguments: file)
      }
    }
    openedFileChannel = opened
  }

  // MARK: - 외부 앱에서 열린 파일 (SceneDelegate에서 호출)

  func handleOpenedURL(_ url: URL) {
    queue.async {
      guard let file = try? self.loadDocument(at: url) else { return }
      DispatchQueue.main.async {
        if self.dartListening, let channel = self.openedFileChannel {
          channel.invokeMethod("fileOpened", arguments: file)
        } else {
          self.pendingFiles.append(file)
        }
      }
    }
  }

  // MARK: - 파일 선택

  private func pickDocument(result: @escaping FlutterResult) {
    guard pendingPick == nil else {
      result(FlutterError(code: "busy", message: "이미 파일 선택 중입니다", details: nil))
      return
    }
    guard let presenter = Self.topViewController() else {
      result(FlutterError(code: "unavailable", message: "화면을 찾을 수 없습니다", details: nil))
      return
    }

    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      let candidates: [UTType?] = [
        UTType("net.daringfireball.markdown"),
        UTType(filenameExtension: "md"),
        UTType(filenameExtension: "markdown"),
        UTType.plainText,
      ]
      let types = candidates.compactMap { $0 }
      // asCopy: false → 사본이 아닌 원본 위치에서 연다.
      picker = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: false)
    } else {
      picker = UIDocumentPickerViewController(
        documentTypes: ["net.daringfireball.markdown", "public.plain-text"], in: .open)
    }
    picker.delegate = self
    picker.allowsMultipleSelection = false
    pendingPick = result
    presenter.present(picker, animated: true)
  }

  // MARK: - 새 파일로 저장

  /// 임시 폴더에 파일을 만든 뒤 내보내기 선택기로 사용자가 고른 위치로 옮긴다.
  private func createDocument(name: String, data: Data, result: @escaping FlutterResult) {
    guard pendingExport == nil else {
      result(FlutterError(code: "busy", message: "이미 저장 위치를 고르는 중입니다", details: nil))
      return
    }
    guard let presenter = Self.topViewController() else {
      result(FlutterError(code: "unavailable", message: "화면을 찾을 수 없습니다", details: nil))
      return
    }

    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let tempURL = tempDir.appendingPathComponent(name)
    do {
      try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      try data.write(to: tempURL)
    } catch {
      result(BridgeError.from(error).flutterError)
      return
    }

    let picker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      // asCopy: false → 임시 파일을 고른 위치로 옮기고, 그 위치의 URL을 돌려받는다.
      picker = UIDocumentPickerViewController(forExporting: [tempURL], asCopy: false)
    } else {
      picker = UIDocumentPickerViewController(url: tempURL, in: .moveToService)
    }
    picker.delegate = self
    pendingExport = (result, tempDir)
    exportPicker = picker
    presenter.present(picker, animated: true)
  }

  private func finishExport(urls: [URL]?) {
    guard let pending = pendingExport else { return }
    let (result, tempDir) = pending
    pendingExport = nil
    exportPicker = nil
    defer { try? FileManager.default.removeItem(at: tempDir) }

    guard let url = urls?.first else {
      result(nil)
      return
    }
    do {
      let accessing = url.startAccessingSecurityScopedResource()
      defer { if accessing { url.stopAccessingSecurityScopedResource() } }
      let bookmark = try url.bookmarkData(
        options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
      result([
        "name": url.lastPathComponent,
        "ref": ["kind": "bookmark", "value": bookmark.base64EncodedString()],
        "location": Self.friendlyLocation(url.path),
      ])
    } catch {
      result(BridgeError.from(error).flutterError)
    }
  }

  /// 북마크가 가리키는 파일에 덮어쓴다. 북마크가 갱신되면 새 ref를 돌려준다.
  private func writeBookmark(_ bookmark: Data, data: Data) throws -> [String: Any]? {
    var stale = false
    let url: URL
    do {
      url = try URL(
        resolvingBookmarkData: bookmark, options: [], relativeTo: nil,
        bookmarkDataIsStale: &stale)
    } catch {
      throw BridgeError.notFound
    }

    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }

    if url.path.contains("/.Trash/") || !FileManager.default.fileExists(atPath: url.path) {
      throw BridgeError.notFound
    }

    var coordinatorError: NSError?
    var writeError: Error?
    NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinatorError) {
      writeURL in
      do {
        try data.write(to: writeURL)
      } catch {
        writeError = error
      }
    }
    if let error = coordinatorError ?? writeError { throw BridgeError.from(error) }

    guard stale,
      let fresh = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    else { return nil }
    return ["ref": ["kind": "bookmark", "value": fresh.base64EncodedString()]]
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    if controller === exportPicker {
      finishExport(urls: urls)
      return
    }
    guard let result = pendingPick else { return }
    pendingPick = nil
    guard let url = urls.first else {
      result(nil)
      return
    }
    runIo(result) { try self.loadDocument(at: url) }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if controller === exportPicker {
      finishExport(urls: nil)
      return
    }
    pendingPick?(nil)
    pendingPick = nil
  }

  // MARK: - 읽기

  /// 선택/전달받은 URL을 읽고, 다음에 다시 열 수 있도록 북마크를 만든다.
  private func loadDocument(at url: URL) throws -> [String: Any] {
    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }

    let data = try coordinatedRead(url)
    let bookmark = try url.bookmarkData(
      options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    return documentMap(url: url, data: data, bookmark: bookmark)
  }

  private func readBookmark(_ bookmark: Data) throws -> [String: Any] {
    var stale = false
    let url: URL
    do {
      url = try URL(
        resolvingBookmarkData: bookmark, options: [], relativeTo: nil,
        bookmarkDataIsStale: &stale)
    } catch {
      throw BridgeError.notFound
    }

    let accessing = url.startAccessingSecurityScopedResource()
    defer { if accessing { url.stopAccessingSecurityScopedResource() } }

    // 파일 앱에서 삭제하면 북마크가 "최근 삭제된 항목"(.Trash)을 가리키게 된다.
    if url.path.contains("/.Trash/") || !FileManager.default.fileExists(atPath: url.path) {
      throw BridgeError.notFound
    }
    let data = try coordinatedRead(url)
    let fresh = stale
      ? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
        ?? bookmark
      : bookmark
    return documentMap(url: url, data: data, bookmark: fresh)
  }

  /// iCloud 등 파일 제공자의 파일도 내려받은 뒤 읽을 수 있도록 NSFileCoordinator를 쓴다.
  private func coordinatedRead(_ url: URL) throws -> Data {
    var coordinatorError: NSError?
    var readError: Error?
    var data: Data?
    NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) {
      readURL in
      do {
        data = try Data(contentsOf: readURL)
      } catch {
        readError = error
      }
    }
    if let error = coordinatorError ?? readError { throw BridgeError.from(error) }
    guard let result = data else { throw BridgeError.io("읽기 실패") }
    return result
  }

  private func documentMap(url: URL, data: Data, bookmark: Data) -> [String: Any] {
    return [
      "name": url.lastPathComponent,
      "bytes": FlutterStandardTypedData(bytes: data),
      "ref": ["kind": "bookmark", "value": bookmark.base64EncodedString()],
      "location": Self.friendlyLocation(url.path),
    ]
  }

  // MARK: - 도우미

  private func runIo(_ result: @escaping FlutterResult, _ block: @escaping () throws -> Any?) {
    queue.async {
      do {
        let value = try block()
        DispatchQueue.main.async { result(value) }
      } catch {
        let bridgeError = (error as? BridgeError) ?? BridgeError.from(error)
        DispatchQueue.main.async { result(bridgeError.flutterError) }
      }
    }
  }

  /// 긴 샌드박스 경로를 "iCloud Drive/폴더/파일.md" 같은 형태로 줄인다.
  static func friendlyLocation(_ path: String) -> String {
    let rules: [(marker: String, label: String)] = [
      ("/Mobile Documents/com~apple~CloudDocs/", "iCloud Drive/"),
      ("/File Provider Storage/", "나의 iPhone/"),
      ("/Documents/Inbox/", "받은 파일/"),
      ("/Documents/", "앱 문서/"),
    ]
    for rule in rules {
      if let range = path.range(of: rule.marker) {
        return rule.label + path[range.upperBound...]
      }
    }
    return path
  }

  private static func topViewController() -> UIViewController? {
    let scene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
      ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
    var top = scene?.windows.first { $0.isKeyWindow }?.rootViewController
      ?? scene?.windows.first?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}

private enum BridgeError: Error {
  case notFound
  case permissionDenied
  case io(String)

  static func from(_ error: Error) -> BridgeError {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain {
      switch nsError.code {
      case NSFileNoSuchFileError, NSFileReadNoSuchFileError:
        return .notFound
      case NSFileReadNoPermissionError:
        return .permissionDenied
      default:
        break
      }
    }
    if nsError.domain == NSPOSIXErrorDomain {
      if nsError.code == Int(ENOENT) { return .notFound }
      if nsError.code == Int(EACCES) || nsError.code == Int(EPERM) { return .permissionDenied }
    }
    return .io(nsError.localizedDescription)
  }

  var flutterError: FlutterError {
    switch self {
    case .notFound:
      return FlutterError(code: "not_found", message: "파일이 없습니다", details: nil)
    case .permissionDenied:
      return FlutterError(code: "permission_denied", message: "권한이 없습니다", details: nil)
    case .io(let message):
      return FlutterError(code: "io_error", message: message, details: nil)
    }
  }
}
