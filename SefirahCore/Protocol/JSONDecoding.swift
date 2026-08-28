import Foundation

extension KeyedDecodingContainer {
    /// Kotlin `Json { encodeDefaults = false }` omits defaulted properties.
    func decodeDefault<T: Decodable>(_ type: T.Type = T.self, forKey key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(type, forKey: key)) ?? fallback
    }
}
