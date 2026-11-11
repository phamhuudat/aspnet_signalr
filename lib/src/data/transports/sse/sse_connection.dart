/// An open Server-Sent Events stream.
abstract interface class SseConnection {
  /// Event data. Closes (or errors) when the stream ends.
  Stream<String> get events;

  /// Closes the stream.
  Future<void> close();
}
