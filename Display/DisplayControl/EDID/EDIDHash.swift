import CryptoKit
import Foundation

enum EDIDHash {
    static func sha256Hex(from data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
