import Foundation

enum M1DDCBrightnessWriteStatus: String, Sendable {
    case success
    case writeAcceptedButReadbackLimited
    case writeFailed
    case readbackUnavailable
}
