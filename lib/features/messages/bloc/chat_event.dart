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

  /// A product of this conversation's shop, shared as a card.
  ///
  /// A message may be words, a card, or both - so an empty body is only empty
  /// when there is no product with it.
  final String? productId;

  /// The message being answered, when this is a reply.
  final String? replyToId;

  const ChatMessageSent(this.body, {this.productId, this.replyToId});
}

/// Closes this conversation from the reader's side, or opens it again.
///
/// Whom it blocks is the thread's own other side, which the server reads from
/// the conversation - there is no id to carry and none to forge.
final class ChatBlockToggled extends ChatEvent {
  const ChatBlockToggled();
}

/// Marks a message to come back to, or takes the mark off.
///
/// The mark is the reader's own: the same message is marked for one side of a
/// thread and not for the other.
final class ChatMessageBookmarkToggled extends ChatEvent {
  final String messageId;

  const ChatMessageBookmarkToggled(this.messageId);
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
