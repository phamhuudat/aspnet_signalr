import '../../domain/entities/connection_info.dart';
import '../../domain/entities/transport_type.dart';
import '../../domain/repositories/negotiation_repository.dart';
import '../datasources/signalr_http_datasource.dart';
import '../mappers/negotiate_mapper.dart';

/// [NegotiationRepository] over HTTP.
class NegotiationRepositoryImpl implements NegotiationRepository {
  /// Creates the repository.
  NegotiationRepositoryImpl(this._dataSource);

  final SignalRHttpDataSource _dataSource;

  @override
  Future<ConnectionInfo> negotiate() async =>
      (await _dataSource.negotiate()).toEntity();

  @override
  Future<void> start(TransportType transport, ConnectionInfo info) =>
      _dataSource.start(transport, info);

  @override
  Future<void> abort(TransportType transport, ConnectionInfo info) =>
      _dataSource.abort(transport, info);
}
