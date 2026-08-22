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
