import SwiftUI
import Network
import CoreTelephony

@MainActor @Observable final class Connectivity {
    var available = false
    var pathMessage = "正在检查网络…"
    var cellularRestricted = false
    var pathPermissionDenied = false
    var permissionDenied: Bool { !available && (cellularRestricted || pathPermissionDenied) }
    private let monitor = NWPathMonitor()
    private let cellular = CTCellularData()
    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let available = path.status == .satisfied
            let permissionDenied = path.unsatisfiedReason == .cellularDenied || path.unsatisfiedReason == .wifiDenied
            let message: String
            if available { message = path.usesInterfaceType(.cellular) ? "当前通过蜂窝数据联网" : "当前网络可用" }
            else {
                switch path.unsatisfiedReason {
                case .cellularDenied: message = "系统未允许此 App 使用蜂窝数据"
                case .wifiDenied: message = "系统未允许此 App 使用无线局域网"
                case .localNetworkDenied: message = "当前网络访问受系统限制"
                default: message = "此 App 当前没有可用的网络连接"
                }
            }
            Task { @MainActor [weak self] in
                self?.available = available; self?.pathMessage = message; self?.pathPermissionDenied = permissionDenied
            }
        }
        monitor.start(queue: DispatchQueue(label: "nga.connectivity"))
        cellular.cellularDataRestrictionDidUpdateNotifier = { [weak self] state in
            let restricted = state == .restricted
            Task { @MainActor [weak self] in self?.cellularRestricted = restricted }
        }
    }
    var message: String {
        cellularRestricted && !available ? "此 App 的蜂窝数据权限已关闭，请到系统设置中允许联网。" : pathMessage
    }
    func describe(_ error: Error) -> String {
        let code = (error as NSError).code
        if (error as NSError).domain == NSURLErrorDomain && code == NSURLErrorNotConnectedToInternet {
            return "此 App 暂时无法联网。请检查系统设置中 NGA Orbit 的无线数据权限，允许后返回重试。"
        }
        return error.localizedDescription
    }
    /// A normal request makes the app itself participate in iOS's first-use network permission flow.
    /// It has no account cookie and its response is not interpreted as a successful forum login.
    func requestAccess(to url: URL) async {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.allowsCellularAccess = true
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        let probe = URLSession(configuration: config)
        defer { probe.invalidateAndCancel() }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.allowsCellularAccess = true
        do {
            let (_, response) = try await probe.data(for: request)
            #if DEBUG
            print("NGA connectivity: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)")
            #endif
        } catch {
            #if DEBUG
            print("NGA connectivity: transport error \((error as NSError).domain) \((error as NSError).code)")
            #endif
        }
    }
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
