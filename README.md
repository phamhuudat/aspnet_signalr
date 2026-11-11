# aspnet_signalr

[![pub package](https://img.shields.io/pub/v/aspnet_signalr.svg)](https://pub.dev/packages/aspnet_signalr)
[![CI](https://github.com/phamhuudat/aspnet_signalr/actions/workflows/ci.yml/badge.svg)](https://github.com/phamhuudat/aspnet_signalr/actions)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A pure Dart client for **ASP.NET SignalR 2.x** (.NET Framework), with first-class support
for **multiple simultaneous connections** and **HTTP proxies**.

Works on Android, iOS, Web, macOS, Windows, Linux and Dart CLI: no native code, no WebView.

> ⚠️ **Which SignalR do you have?**
> This package is for the classic **ASP.NET SignalR** (`Microsoft.AspNet.SignalR`, endpoints like `/signalr/negotiate`).
> If your server uses **ASP.NET Core SignalR** (`Microsoft.AspNetCore.SignalR`), use
> [`signalr_netcore`](https://pub.dev/packages/signalr_netcore) or [`signalr_core`](https://pub.dev/packages/signalr_core) instead.

## Features

- ✅ Pure Dart: runs on every Flutter platform and in plain Dart
- ✅ Multiple independent connections, plus `HubConnectionManager` to manage them together
- ✅ Multiple hubs on one connection
- ✅ All practical transports: **WebSockets, Server-Sent Events, Long Polling**, and `auto` fallback (same order as the official JS client)
- ✅ Works with servers that disable WebSockets (`TryWebSockets: false`)
- ✅ Automatic reconnect that keeps your groups and message cursor (`messageId` + `groupsToken`)
- ✅ Keep-alive monitoring with a `connectionSlow` warning
- ✅ Typed `invoke<T>()` that returns a `Future` and throws typed exceptions
- ✅ `Stream`-based connection state
- ✅ HTTP proxy per connection (host/port, proxy auth, bypass list, environment, custom resolver) for every transport
- ✅ Custom headers, query string, `http.Client` and logger

## Installation

```bash
dart pub add aspnet_signalr
# or
flutter pub add aspnet_signalr
```

## Quick start

```dart
import 'package:aspnet_signalr/aspnet_signalr.dart';

Future<void> main() async {
  final connection = HubConnectionBuilder()
      .withUrl('https://example.com') // "/signalr" is appended (useDefaultPath: true)
      .withAutomaticReconnect()
      .build();

  // Hub proxies must be created BEFORE start().
  final market = connection.createHubProxy('marketHub');

  market.on('priceChanged', (args) {
    final update = args[0] as Map<String, dynamic>;
    print('${update['symbol']}: ${update['price']}');
  });

  connection.stateStream.listen((state) => print('State: $state'));

  await connection.start();
  print('Connected with ${connection.transport}'); // e.g. TransportType.serverSentEvents

  final count = await market.invoke<int>('getSymbolCount');
  print('Symbols: $count');

  await connection.stop();
}
```

## Server URL

| You pass | Requests go to |
|---|---|
| `withUrl('https://host')` | `https://host/signalr/negotiate`, … |
| `withUrl('https://host/app')` | `https://host/app/signalr/negotiate`, … |
| `withUrl('https://host/app/signalr', useDefaultPath: false)` | `https://host/app/signalr/negotiate`, … |

This matches `$.hubConnection(url)` in the official JavaScript client.

## Multiple connections

Each `HubConnection` is fully independent: its own transport, proxy, state, reconnect loop
and handlers. Stopping one never affects the others.

```dart
HubConnection market(String url) => HubConnectionBuilder()
    .withUrl(url)
    .withAutomaticReconnect()
    .build();

final exchangeA = market('https://a.example.com');
final exchangeB = market('https://b.example.com');
final derivatives = market('https://d.example.com');

exchangeA.createHubProxy('hubA').on('update', (args) => print('A: $args'));
exchangeB.createHubProxy('hubB').on('update', (args) => print('B: $args'));
derivatives.createHubProxy('hubD').on('update', (args) => print('D: $args'));

final manager = HubConnectionManager()
  ..add('a', exchangeA)
  ..add('b', exchangeB)
  ..add('d', derivatives);

await manager.startAll();
await manager.stop('d'); // a and b keep running
await manager.stopAll();
```

## Multiple hubs on one connection

```dart
final connection = HubConnectionBuilder().withUrl(url).build();
final chat = connection.createHubProxy('chatHub');
final notify = connection.createHubProxy('notificationHub');
await connection.start(); // one connection, two hubs
```

## Connection state

```dart
connection.stateStream.listen((state) {
  switch (state) {
    case ConnectionState.connecting:
    case ConnectionState.connected:
    case ConnectionState.reconnecting:
    case ConnectionState.disconnected:
      break;
  }
});

connection.onConnectionSlow(() => print('Connection is slow'));
```

## Reconnect

```dart
HubConnectionBuilder()
    .withUrl(url)
    .withAutomaticReconnect() // default delays: 0s, 2s, 10s, 30s
    // or: .withAutomaticReconnect(delays: [Duration.zero, Duration(seconds: 5)])
    // or: .withReconnectPolicy(MyPolicy())
    .build();
```

When the transport is lost the state becomes `reconnecting`:

- Within the reconnect window (`DisconnectTimeout` + `KeepAliveTimeout`, counted from the last
  frame), the client calls `/signalr/reconnect` with the last `messageId` and `groupsToken`, so
  **group membership and missed messages are kept** and `connectionId` does not change.
- After the window, with `withAutomaticReconnect()` / `withReconnectPolicy()`, a **new connection is
  negotiated** (new `connectionId`, handlers kept). Server-side groups are lost: join them again in
  `onReconnected` when `newConnection` is `true`.
- Without a policy, the client behaves like the JavaScript client: it retries `/reconnect` every
  2 seconds during the window, then reports `disconnected`.
- The state becomes `disconnected` only when the policy gives up (or on `stop()`).

```dart
connection.onReconnecting((error) => print('Lost: $error'));
connection.onReconnected((newConnection) {
  if (newConnection) hub.invoke('joinGroup', ['room-1']);
});
connection.onClosed((error) => print('Closed: $error'));

// Never give up (exponential back-off, capped at 30s):
HubConnectionBuilder().withUrl(url).withReconnectPolicy(const ForeverReconnectPolicy()).build();
```

> A failed **first** `start()` is not retried automatically: it throws, and you decide.

## Transports

| `TransportType` | Behavior |
|---|---|
| `auto` (default) | WebSockets if the server allows it (`TryWebSockets`), then Server-Sent Events, then Long Polling |
| `webSockets` | WebSockets only |
| `serverSentEvents` | SSE for receiving, HTTP POST for sending |
| `longPolling` | Long Polling only (works through almost any proxy) |

```dart
HubConnectionBuilder().withUrl(url).withTransport(TransportType.serverSentEvents).build();
```

## Authentication

```dart
HubConnectionBuilder()
    .withUrl(url,
        headers: {'Authorization': 'Bearer $token'}, // Android, iOS, desktop
        queryParameters: {'access_token': token})    // works everywhere, incl. Web
    .build();
```

> **Web:** browsers do not allow custom headers on WebSocket or EventSource connections.
> Use `queryParameters` or cookies when targeting Flutter Web.

## Proxy

Route all SignalR traffic (negotiate, start, send, SSE, long polling **and** WebSocket) through an HTTP proxy.
Each connection can have its own proxy.

```dart
// Fixed proxy, optionally with authentication
HubConnectionBuilder()
    .withUrl(url)
    .withProxy(const ProxyConfig(
      host: 'proxy.example.com',
      port: 8080,
      username: 'user',          // optional, Basic proxy auth
      password: 'secret',
      bypass: ['localhost', '*.internal.example.com'],
    ))
    .build();

// Read HTTP_PROXY / HTTPS_PROXY / NO_PROXY from the environment
HubConnectionBuilder().withUrl(url).withProxy(ProxyConfig.fromEnvironment()).build();

// Decide per request (PAC-style string)
HubConnectionBuilder()
    .withUrl(url)
    .withProxy(ProxyConfig.custom((uri) =>
        uri.host.startsWith('d.') ? 'PROXY proxy.example.com:8080' : 'DIRECT'))
    .build();
```

**Debugging with Charles / Proxyman / mitmproxy:**

```dart
.withProxy(ProxyConfig(
  host: '192.168.1.10',
  port: 8888,
  allowBadCertificates: kDebugMode, // ⚠️ NEVER enable in release builds
))
```

> **Notes**
> - Flutter on Android/iOS does **not** use the device's system proxy automatically.
>   Read it yourself (for example with a system-proxy plugin) and pass it to `ProxyConfig`.
> - **Web:** proxy settings are ignored (a warning is logged). The browser applies its own proxy configuration.
> - If you pass both `withHttpClient()` and `withProxy()`, `build()` throws an `ArgumentError`.
> - Proxy credentials may contain `@`, `:` and other symbols in the password. Because `dart:io`
>   sends them on the `CONNECT` tunnel only from its PAC string, `build()` rejects values it would
>   corrupt: `;` anywhere, `:` in the username, an empty username, or leading/trailing spaces.

## Error handling

```dart
try {
  await hub.invoke('placeOrder', [order]);
} on HubInvocationException catch (e) {
  print('Server error: ${e.message} ${e.errorData}');
} on SignalRTimeoutException {
  print('No response from server');
} on SignalRException catch (e) {
  print('Connection error: $e');
}
```

Invocations have a default timeout of 30 seconds (`withInvocationTimeout()` on the builder,
or `hub.invoke<T>(method, args, timeout)`). Pending invocations fail when the transport is lost.

| Exception | When |
|---|---|
| `NegotiateException` | `/negotiate` or `/start` failed (wrong URL, auth, hub name) |
| `ProxyException` | The proxy cannot be reached, rejected the credentials (407) or refused the tunnel. Errors of the server behind the proxy keep their own type |
| `TransportException` | No transport could connect, or the transport failed |
| `HubInvocationException` | The server method threw an error |
| `HubConnectionManagerException` | `startAll()` failed for some connections (`errors` per name) |
| `SignalRTimeoutException` | Invocation or connect timed out |

## Logging

```dart
HubConnectionBuilder()
    .withUrl(url)
    .withLogger(PrintLogger(level: LogLevel.debug))
    .build();
```

## Migrating from `signalr_flutter`

| `signalr_flutter` | `aspnet_signalr` |
|---|---|
| `SignalR(baseUrl, hubName, hubMethods: [...])` | `HubConnectionBuilder().withUrl(baseUrl).build()` + `createHubProxy(hubName)` |
| `hubCallback: (method, message) {}` (message is a JSON string) | `hub.on('method', (args) {})` (args are already decoded) |
| `statusChangeCallback` | `connection.stateStream` |
| `invokeMethod(name, arguments: [...])` → `String` | `hub.invoke<T>(name, [...])` → `T` |
| `connect()` / `stop()` / `reconnect()` | `start()` / `stop()` / automatic |
| `Transport.auto / serverSentEvents / longPolling` | `TransportType.auto / serverSentEvents / longPolling` (+ `webSockets`) |
| Native plugin (Android/iOS only) | Pure Dart (all platforms) |

## Limitations

- Supports the ASP.NET SignalR protocol version 1.5 (SignalR 2.x servers). SignalR 1.x is not tested.
- The Forever Frame transport (old Internet Explorer only) is not implemented.
- Hub proxies must be created before `start()`, the same rule as the official JavaScript client.

## Contributing

Issues and PRs are welcome. Run `dart test` before opening a PR. The integration tests use
the fake server in `tool/fake_server`.

## License

MIT. See [LICENSE](LICENSE).

Protocol behavior is based on the official [ASP.NET SignalR](https://github.com/SignalR/SignalR) JavaScript client by Microsoft (Apache-2.0).
This package is an independent implementation and is not affiliated with Microsoft.
