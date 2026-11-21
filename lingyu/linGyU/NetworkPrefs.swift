import Foundation
import SwiftUI

/// 网络协议屏: which network abilities the agents may use. Every protocol
/// defaults to Deny; there is no Allow option — an agent that needs a
/// protocol asks first. The DNS setting (domestic presets + custom) is
/// here too.
///
/// Honest limitation: the computer-side host does not read these settings
/// yet, so today they are stored on this device and shown in the app.
/// Enforcement on the host is an open gap, stated on the screen itself.
@MainActor
final class NetworkPrefs: ObservableObject {
    static let protocols: [(key: String, label: String)] = [
        ("ssh", "SSH"),
        ("emailSend", "发邮件"),
        ("mailbox", "收件箱"),
        ("database", "数据库"),
        ("ftp", "FTP"),
        ("externalDNS", "外部 DNS"),
        ("tcpUdp", "TCP/UDP 直连"),
    ]
    static let dnsModes: [(key: String, label: String)] = [
        ("system", "跟随系统"),
        ("alibaba", "阿里 DNS"),
        ("tencent", "腾讯 DNS"),
        ("114", "114 DNS"),
        ("custom", "自定义"),
    ]
    static let dnsAddresses: [String: String] = [
        "alibaba": "223.5.5.5",
        "tencent": "119.29.29.29",
        "114": "114.114.114.114",
    ]

    @Published var ssh: String { didSet { save("ssh", ssh) } }
    @Published var emailSend: String { didSet { save("emailSend", emailSend) } }
    @Published var mailbox: String { didSet { save("mailbox", mailbox) } }
    @Published var database: String { didSet { save("database", database) } }
    @Published var ftp: String { didSet { save("ftp", ftp) } }
    @Published var externalDNS: String { didSet { save("externalDNS", externalDNS) } }
    @Published var tcpUdp: String { didSet { save("tcpUdp", tcpUdp) } }
    @Published var dnsMode: String { didSet { save("dnsMode", dnsMode) } }
    @Published var customDNS: String { didSet { save("customDNS", customDNS) } }

    init() {
        ssh = UserDefaults.standard.string(forKey: "cn.lingyu.net.ssh") ?? "deny"
        emailSend = UserDefaults.standard.string(forKey: "cn.lingyu.net.emailSend") ?? "deny"
        mailbox = UserDefaults.standard.string(forKey: "cn.lingyu.net.mailbox") ?? "deny"
        database = UserDefaults.standard.string(forKey: "cn.lingyu.net.database") ?? "deny"
        ftp = UserDefaults.standard.string(forKey: "cn.lingyu.net.ftp") ?? "deny"
        externalDNS = UserDefaults.standard.string(forKey: "cn.lingyu.net.externalDNS") ?? "deny"
        tcpUdp = UserDefaults.standard.string(forKey: "cn.lingyu.net.tcpUdp") ?? "deny"
        dnsMode = UserDefaults.standard.string(forKey: "cn.lingyu.net.dnsMode") ?? "system"
        customDNS = UserDefaults.standard.string(forKey: "cn.lingyu.net.customDNS") ?? ""
    }

    /// The DNS address actually in effect for the chosen mode, if any.
    var dnsAddress: String? {
        if dnsMode == "custom" { return customDNS.isEmpty ? nil : customDNS }
        return Self.dnsAddresses[dnsMode]
    }

    private func save(_ key: String, _ value: String) {
        UserDefaults.standard.set(value, forKey: "cn.lingyu.net.\(key)")
    }
}
