import Foundation

/// 客户端错误统一出口（中文信息）。
public enum APIError: Error, Equatable {
    case invalidServer
    case network(String)
    case http(status: Int, message: String)
    case decoding
    case cancelled

    public var message: String {
        switch self {
        case .invalidServer:
            return "服务器地址无效，请先在设置里检查"
        case .network(let reason):
            return "连接服务器失败：\(reason)"
        case .http(let status, let message):
            if !message.isEmpty { return message }
            return "服务器返回错误（HTTP \(status)）"
        case .decoding:
            return "服务器返回的数据无法解析，可能版本不匹配"
        case .cancelled:
            return "已取消"
        }
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? { message }
}

extension URLError {
    /// 面向用户的中文原因。
    public var yue2Reason: String {
        switch code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "设备没有可用网络"
        case .timedOut:
            return "连接超时"
        case .cannotConnectToHost:
            return "无法连接主机，请检查地址与端口"
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate:
            return "TLS 握手失败（局域网测试可改用 http://）"
        case .cancelled:
            return "请求已取消"
        default:
            return localizedDescription
        }
    }
}
