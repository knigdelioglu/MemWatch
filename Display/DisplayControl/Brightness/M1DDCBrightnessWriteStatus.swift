import Foundation

enum M1DDCBrightnessWriteStatus: String, Sendable {
    case success
    case writeAcceptedReadbackUncertain
    @available(*, deprecated, message: "Use writeAcceptedReadbackUncertain")
    case writeAcceptedButReadbackLimited
    case writeFailed
    case readbackUnavailable
}
