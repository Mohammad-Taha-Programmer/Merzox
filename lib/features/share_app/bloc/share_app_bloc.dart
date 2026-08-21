import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/share_app_service.dart';
import 'share_app_event.dart';
import 'share_app_state.dart';

class ShareAppBloc extends Bloc<ShareAppEvent, ShareAppState> {
  final ShareAppService _shareService;

  ShareAppBloc({ShareAppService? shareService})
    : _shareService = shareService ?? ShareAppService(),
      super(const ShareAppState()) {
    on<ShareAppStarted>(_onStarted);
    on<ShareAppTargetRequested>(_onTargetRequested);
    on<ShareAppLinkCopied>(_onLinkCopied);
    on<ShareAppStoreOpened>(_onStoreOpened);
  }

  void _onStarted(ShareAppStarted event, Emitter<ShareAppState> emit) {
    final languageCode = event.languageCode == 'en' ? 'en' : 'ar';
    if (state.status != ShareAppStatus.initial &&
        state.languageCode == languageCode) {
      return;
    }

    final store = _shareService.currentStore();
    emit(
      state.copyWith(
        status: ShareAppStatus.ready,
        languageCode: languageCode,
        store: store,
        payload: _shareService.payloadFor(
          languageCode: languageCode,
          storeUri: store.uri,
        ),
        clearActiveTarget: true,
        messageCode: '',
      ),
    );
  }

  Future<void> _onTargetRequested(
    ShareAppTargetRequested event,
    Emitter<ShareAppState> emit,
  ) async {
    if (state.status == ShareAppStatus.sharing ||
        state.store == null ||
        state.payload == null) {
      return;
    }

    emit(
      state.copyWith(
        status: ShareAppStatus.sharing,
        activeTarget: event.target,
        messageCode: '',
      ),
    );

    try {
      final outcome = await _shareService.share(
        target: event.target,
        store: state.store!,
        payload: state.payload!,
        sharePositionOrigin: event.sharePositionOrigin,
      );
      emit(
        state.copyWith(
          status: outcome == ShareAppOutcome.dismissed
              ? ShareAppStatus.ready
              : ShareAppStatus.success,
          clearActiveTarget: true,
          messageCode: outcome == ShareAppOutcome.dismissed
              ? ''
              : 'shareApp.opened',
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: ShareAppStatus.failure,
          clearActiveTarget: true,
          messageCode: 'shareApp.shareError',
        ),
      );
    }
  }

  Future<void> _onLinkCopied(
    ShareAppLinkCopied event,
    Emitter<ShareAppState> emit,
  ) async {
    if (state.store == null || state.status == ShareAppStatus.sharing) return;

    emit(
      state.copyWith(
        status: ShareAppStatus.sharing,
        clearActiveTarget: true,
        messageCode: '',
      ),
    );

    try {
      await _shareService.copyStoreLink(state.store!);
      emit(
        state.copyWith(
          status: ShareAppStatus.success,
          clearActiveTarget: true,
          messageCode: 'shareApp.copied',
        ),
      );
    } catch (_) {
      emit(
        state.copyWith(
          status: ShareAppStatus.failure,
          clearActiveTarget: true,
          messageCode: 'shareApp.copyError',
        ),
      );
    }
  }

  Future<void> _onStoreOpened(
    ShareAppStoreOpened event,
    Emitter<ShareAppState> emit,
  ) async {
    if (state.store == null || state.status == ShareAppStatus.sharing) return;

    emit(
      state.copyWith(
        status: ShareAppStatus.sharing,
        clearActiveTarget: true,
        messageCode: '',
      ),
    );
    final opened = await _shareService.openStore(state.store!);
    emit(
      state.copyWith(
        status: opened ? ShareAppStatus.success : ShareAppStatus.failure,
        clearActiveTarget: true,
        messageCode: opened ? 'shareApp.storeOpened' : 'shareApp.shareError',
      ),
    );
  }
}
