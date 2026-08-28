import AppKit
import Foundation

/// Applies inbound `ClipboardInfo` to an `NSPasteboard` (text or decoded image).
public enum ClipboardApply {
    @discardableResult
    public static func apply(_ info: ClipboardInfo, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        if info.clipboardType.lowercased().hasPrefix("image/"),
           let data = Data(base64Encoded: info.content),
           let image = NSImage(data: data)
        {
            return pasteboard.writeObjects([image])
        }
        return pasteboard.setString(info.content, forType: .string)
    }

    @discardableResult
    public static func applyFile(_ url: URL, mimeType: String?, to pasteboard: NSPasteboard = .general) -> Bool {
        pasteboard.clearContents()
        if let mime = mimeType?.lowercased(), mime.hasPrefix("image/"),
           let data = try? Data(contentsOf: url),
           let image = NSImage(data: data)
        {
            return pasteboard.writeObjects([image])
        }
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return pasteboard.setString(text, forType: .string)
        }
        return pasteboard.writeObjects([url as NSURL])
    }
}
