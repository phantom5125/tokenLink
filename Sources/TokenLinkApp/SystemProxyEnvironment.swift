import Foundation
import SystemConfiguration

/// Builds proxy environment variables from macOS system proxy settings.
///
/// URLSession honors the system proxy automatically, but local CLI
/// subprocesses (the Codex app-server's HTTP stack) only read `*_PROXY`
/// environment variables — and a GUI app launched from Finder has none.
/// Without this bridge the Codex fetch fails behind a system-level proxy.
public enum SystemProxyEnvironment {
  public static func current() -> [String: String] {
    let settings =
      CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] ?? [:]
    return environment(from: settings)
  }

  /// Pure mapping from a system proxy dictionary to environment variables,
  /// kept separate for testing.
  public static func environment(from settings: [String: Any]) -> [String: String] {
    var environment: [String: String] = [:]

    func enabled(_ key: String) -> Bool {
      (settings[key] as? Int ?? 0) == 1
    }
    func httpURL(_ hostKey: String, _ portKey: String) -> String? {
      guard let host = settings[hostKey] as? String, !host.isEmpty else { return nil }
      let port = settings[portKey] as? Int
      return port.map { "http://\(host):\($0)" } ?? "http://\(host)"
    }

    if enabled("HTTPSEnable"), let url = httpURL("HTTPSProxy", "HTTPSPort") {
      environment["HTTPS_PROXY"] = url
      environment["https_proxy"] = url
    }
    if enabled("HTTPEnable"), let url = httpURL("HTTPProxy", "HTTPPort") {
      environment["HTTP_PROXY"] = url
      environment["http_proxy"] = url
    }
    if environment.isEmpty,
      enabled("SOCKSEnable"),
      let host = settings["SOCKSProxy"] as? String, !host.isEmpty
    {
      let port = settings["SOCKSPort"] as? Int
      let url = port.map { "socks5://\(host):\($0)" } ?? "socks5://\(host)"
      environment["ALL_PROXY"] = url
      environment["all_proxy"] = url
    }
    return environment
  }
}
