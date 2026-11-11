## 0.0.1

- Initial development version (not published).
- ASP.NET SignalR 2.x protocol 1.5: negotiate, connect, start, send, abort,
  reconnect, poll.
- Transports: WebSockets, Server-Sent Events, Long Polling, `auto` fallback.
- Multiple independent connections and `HubConnectionManager`.
- Hub proxies with `on`/`off`/`invoke<T>`, hub state, typed exceptions.
- Keep-alive monitor (`onConnectionSlow`), reconnect with `messageId` and
  `groupsToken`, pluggable reconnect policies.
- Per-connection HTTP proxy (fixed, authenticated, bypass list, environment,
  custom resolver) for every transport on `dart:io` platforms.
