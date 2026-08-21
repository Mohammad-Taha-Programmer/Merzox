enum MessagesFilter { all, unread }

extension MessagesFilterValue on MessagesFilter {
  bool get unreadOnly => this == MessagesFilter.unread;
}

sealed class MessagesEvent {
  const MessagesEvent();
}

final class MessagesStarted extends MessagesEvent {
  const MessagesStarted();
}

final class MessagesFilterChanged extends MessagesEvent {
  final MessagesFilter filter;

  const MessagesFilterChanged(this.filter);
}

final class MessagesRefreshRequested extends MessagesEvent {
  const MessagesRefreshRequested();
}

final class MessagesLoadMoreRequested extends MessagesEvent {
  const MessagesLoadMoreRequested();
}

/// Emitted after a thread is opened so the list drops its badge without a
/// full reload.
final class MessagesThreadRead extends MessagesEvent {
  final String conversationId;

  const MessagesThreadRead(this.conversationId);
}
