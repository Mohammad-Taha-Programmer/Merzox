sealed class ChatEvent {
  const ChatEvent();
}

final class ChatStarted extends ChatEvent {
  const ChatStarted();
}

/// Used from a product or store page, where the thread may not exist yet.
final class ChatOpenedForBusiness extends ChatEvent {
  final String businessId;

  const ChatOpenedForBusiness(this.businessId);
}

final class ChatMessageSent extends ChatEvent {
  final String body;

  const ChatMessageSent(this.body);
}

final class ChatOlderMessagesRequested extends ChatEvent {
  const ChatOlderMessagesRequested();
}

final class ChatRefreshRequested extends ChatEvent {
  const ChatRefreshRequested();
}

/// Internal synchronization request raised by the realtime transport.
///
/// The event stays inside the BLoC boundary: Socket.IO never writes chat state
/// directly. The BLoC always re-reads authoritative REST/MongoDB truth.
final class ChatRealtimeSyncRequested extends ChatEvent {
  const ChatRealtimeSyncRequested();
}

/// Moves to another occurrence of the searched-for phrase.
///
/// +1 for the arrow pointing forward through the conversation, -1 back. The
/// walk wraps, so the reader at the last of nine reaches the first again
/// rather than pressing a dead button.
final class ChatMatchStepped extends ChatEvent {
  final int delta;

  const ChatMatchStepped(this.delta);
}
