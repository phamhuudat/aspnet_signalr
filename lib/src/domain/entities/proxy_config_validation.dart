import 'proxy_config.dart';

/// Returns why [config] cannot be used, or `null` when it is valid.
///
/// On `dart:io` the credentials must travel inside the PAC string
/// (`PROXY user:password@host:port`): it is the only way `dart:io` sends
/// them on the `CONNECT` tunnel used for `https`/`wss`. That string is
/// split on `;`, the user ends at the first `:`, and both parts are trimmed,
/// so values that would be silently corrupted are rejected here. The
/// password itself is never included in the message.
String? proxyConfigProblem(ProxyConfig config) {
  if (config.resolver != null || config.useEnvironment) return null;
  final host = config.host!;
  if (host.trim().isEmpty ||
      host.trim() != host ||
      host.contains(';') ||
      host.contains('@') ||
      host.contains(' ')) {
    return 'invalid proxy host "$host"';
  }
  final port = config.port!;
  if (port <= 0 || port > 65535) return 'invalid proxy port $port';

  final user = config.username;
  final password = config.password;
  if (user == null) {
    return password == null ? null : 'a proxy password requires a username';
  }
  if (user.isEmpty) return 'the proxy username must not be empty';
  if (user.contains(':')) return 'the proxy username must not contain ":"';
  if (user.contains(';')) return 'the proxy username must not contain ";"';
  if (user.trim() != user) {
    return 'the proxy username must not start or end with whitespace';
  }
  if (password != null) {
    if (password.contains(';')) {
      return 'the proxy password must not contain ";"';
    }
    if (password.trim() != password) {
      return 'the proxy password must not start or end with whitespace';
    }
  }
  return null;
}
