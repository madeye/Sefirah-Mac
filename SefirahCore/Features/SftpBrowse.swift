import Foundation

public enum SftpBrowse {
    public static func finderURL(
        host: String,
        port: Int,
        username: String,
        password: String,
        path: String? = nil
    ) -> URL? {
        let normalized = normalizePath(path)
        let hostPart = formatHost(host)
        let user = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
        let pass = password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed) ?? password
        let string = "sftp://\(user):\(pass)@\(hostPart):\(port)\(normalized)"
        return URL(string: string)
    }

    public static func finderURLWithoutPassword(host: String, port: Int, username: String, path: String? = nil) -> URL? {
        let normalized = normalizePath(path)
        let hostPart = formatHost(host)
        let user = username.addingPercentEncoding(withAllowedCharacters: .urlUserAllowed) ?? username
        return URL(string: "sftp://\(user)@\(hostPart):\(port)\(normalized)")
    }

    private static func normalizePath(_ path: String?) -> String {
        var value = path ?? "/"
        if !value.hasPrefix("/") { value = "/" + value }
        if !value.hasSuffix("/") { value += "/" }
        return value
    }

    private static func formatHost(_ host: String) -> String {
        host.contains(":") ? "[\(host)]" : host
    }
}
