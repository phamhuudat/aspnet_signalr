/// The transport used to talk to an ASP.NET SignalR 2.x server.
enum TransportType {
  /// Try [webSockets] (only if the server allows it), then
  /// [serverSentEvents], then [longPolling].
  auto(null),

  /// WebSockets only.
  webSockets('webSockets'),

  /// Server-Sent Events for receiving, HTTP POST for sending.
  serverSentEvents('serverSentEvents'),

  /// Long polling only.
  longPolling('longPolling');

  const TransportType(this.queryValue);

  /// The value of the `transport` query parameter, `null` for [auto].
  final String? queryValue;
}
