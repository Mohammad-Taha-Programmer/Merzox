import 'package:flutter_bloc/flutter_bloc.dart';

import 'messages_event.dart';
import 'messages_state.dart';

class MessagesBloc extends Bloc<MessagesEvent, MessagesState> {
  MessagesBloc() : super(const MessagesState()) {
    on<MessagesStarted>(_onStarted);
  }

  Future<void> _onStarted(
    MessagesStarted event,
    Emitter<MessagesState> emit,
  ) async {
    emit(state.copyWith(status: MessagesStatus.loading));

    // Chat persistence will move here when real-time messaging is connected.
    emit(state.copyWith(status: MessagesStatus.ready, threads: const []));
  }
}
