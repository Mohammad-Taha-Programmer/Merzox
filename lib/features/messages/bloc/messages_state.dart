enum MessagesStatus { initial, loading, ready }

final class MessageThread {
  final String id;
  final String name;
  final String lastMessage;
  final String time;
  final int unreadCount;

  const MessageThread({
    required this.id,
    required this.name,
    required this.lastMessage,
    required this.time,
    required this.unreadCount,
  });
}

final class MessagesState {
  final MessagesStatus status;
  final List<MessageThread> threads;

  const MessagesState({
    this.status = MessagesStatus.initial,
    this.threads = const [],
  });

  MessagesState copyWith({
    MessagesStatus? status,
    List<MessageThread>? threads,
  }) {
    return MessagesState(
      status: status ?? this.status,
      threads: threads ?? this.threads,
    );
  }
}
