import '../entities/transport_type.dart';
import 'client_transport.dart';
import 'negotiation_repository.dart';

/// Everything one `start()` needs: HTTP endpoints and transports, sharing a
/// single HTTP client (and proxy).
abstract interface class ConnectionSession {
  /// Negotiate, start and abort.
  NegotiationRepository get negotiation;

  /// Creates a transport. [TransportType.auto] returns the fallback chain.
  ClientTransport createTransport(TransportType type);

  /// Releases the HTTP client.
  void dispose();
}

/// Creates a [ConnectionSession] per `start()`.
abstract interface class ConnectionSessionFactory {
  /// Creates a session for [hubNames].
  ConnectionSession create(List<String> hubNames);
}
