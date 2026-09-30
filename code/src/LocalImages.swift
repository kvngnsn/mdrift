import Cocoa
import WebKit

final class LocalImages: NSObject, WKURLSchemeHandler {
    var directory: URL?
    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let root = directory?.resolvingSymlinksInPath(),
            let request = urlSchemeTask.request.url
        else {
            urlSchemeTask.didFailWithError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return
        }
        let relative = String(request.path.dropFirst())
        let file = root.appendingPathComponent(relative).standardizedFileURL
            .resolvingSymlinksInPath()
        let types = [
            "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif",
            "webp": "image/webp", "svg": "image/svg+xml", "avif": "image/avif",
            "heic": "image/heic",
        ]
        guard file.path.hasPrefix(root.path + "/"),
            let type = types[file.pathExtension.lowercased()],
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
            (attributes[.size] as? NSNumber)?.intValue ?? Int.max < 25_000_000,
            let data = try? Data(contentsOf: file)
        else {
            urlSchemeTask.didFailWithError(
                NSError(domain: NSURLErrorDomain, code: NSURLErrorNoPermissionsToReadFile))
            return
        }
        urlSchemeTask.didReceive(
            URLResponse(
                url: request, mimeType: type, expectedContentLength: data.count,
                textEncodingName: nil))
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
