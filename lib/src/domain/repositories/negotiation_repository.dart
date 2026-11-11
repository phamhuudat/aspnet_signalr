import '../entities/connection_info.dart';
import '../entities/transport_type.dart';

/// HTTP endpoints of the protocol that are not transport specific.
abstract interface class NegotiationRepository {
  /// `GET /negotiate`.
  Future<ConnectionInfo> negotiate();

  /// `GET /start`, after the transport is initialized.
  Future<void> start(TransportType transport, ConnectionInfo info);

  /// `POST /abort`. Never throws.
  Future<void> abort(TransportType transport, ConnectionInfo info);
}
