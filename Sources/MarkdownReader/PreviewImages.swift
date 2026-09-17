import Foundation
import UniformTypeIdentifiers
import WebKit

/// Serves the document's local images to the preview web view.
///
/// The page is loaded from a string with no base URL, so WebKit gives it no
/// file access at all. Local images go through this custom scheme instead: the
/// renderer resolves the path the same way it resolves links, and the handler
/// reads the file on demand. Remote `http(s)` images are fetched by WebKit.
enum PreviewImages {
    static let scheme = "mdimg"
    static let maximumBytes = 20_000_000

    /// The `src` for an image, or nil when the source cannot be shown.
    static func source(for source: String, baseURL: URL?) -> String? {
        let base = baseURL?.deletingLastPathComponent().appendingPathComponent("")
        guard let url = URL(string: source, relativeTo: base)?.absoluteURL else { return nil }
        switch url.scheme?.lowercased() {
        case "http", "https":
            return url.absoluteString
        case "file":
            var components = URLComponents()
            components.scheme = scheme
            components.host = ""
            components.path = url.path
            return components.url?.absoluteString
        default:
            return nil
        }
    }
}

/// Answers `mdimg:///absolute/path` requests with the file's bytes.
///
/// The read is synchronous and finishes inside `start`, so a `stop` can never
/// arrive mid-flight and there is no task state to guard. Local images are
/// small enough for this to be invisible; the size cap keeps it that way.
final class PreviewImageHandler: NSObject, WKURLSchemeHandler {
    func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
        guard let url = task.request.url else { task.didFailWithError(URLError(.badURL)); return }
        let file = URL(fileURLWithPath: url.path)
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= PreviewImages.maximumBytes, let data = try? Data(contentsOf: file) else {
            task.didFailWithError(URLError(.cannotOpenFile))
            return
        }
        let mime = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        task.didReceive(URLResponse(url: url, mimeType: mime, expectedContentLength: data.count, textEncodingName: nil))
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
}
