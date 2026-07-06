import CryptoKit
import Foundation

public enum SHA256Checksum {
    public static func hexDigest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
