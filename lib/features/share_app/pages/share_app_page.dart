import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/colors.dart';
import '../../../services/share_app_service.dart';
import '../bloc/share_app_bloc.dart';
import '../bloc/share_app_event.dart';
import '../bloc/share_app_state.dart';

class ShareAppPage extends StatefulWidget {
  const ShareAppPage({super.key});

  @override
  State<ShareAppPage> createState() => _ShareAppPageState();
}

class _ShareAppPageState extends State<ShareAppPage> {
  String? _requestedLanguageCode;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final languageCode = context.locale.languageCode == 'en' ? 'en' : 'ar';
    if (_requestedLanguageCode == languageCode) return;

    _requestedLanguageCode = languageCode;
    context.read<ShareAppBloc>().add(ShareAppStarted(languageCode));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ShareAppBloc, ShareAppState>(
      listenWhen: (previous, current) =>
          current.messageCode.isNotEmpty &&
          (previous.messageCode != current.messageCode ||
              previous.status != current.status),
      listener: (context, state) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(state.messageCode.tr())));
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: Column(
              children: [
                const _ShareAppHeader(),
                Expanded(
                  child: state.store == null || state.payload == null
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: MerzoxColors.kColor3D5A80,
                          ),
                        )
                      : _ShareAppContent(state: state),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ShareAppHeader extends StatelessWidget {
  const _ShareAppHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 82,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'shareApp.title'.tr(),
            style: const TextStyle(
              color: MerzoxColors.kColor2B2B2B,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const PositionedDirectional(
            start: 8,
            child: BackButton(color: MerzoxColors.kColor5E5E5E),
          ),
        ],
      ),
    );
  }
}

class _ShareAppContent extends StatelessWidget {
  final ShareAppState state;

  const _ShareAppContent({required this.state});

  @override
  Widget build(BuildContext context) {
    final store = state.store!;
    final busy = state.status == ShareAppStatus.sharing;

    return ListView(
      padding: const EdgeInsetsDirectional.fromSTEB(20, 8, 20, 30),
      children: [
        Center(
          child: Container(
            width: 78,
            height: 78,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: MerzoxColors.kColorFEE3DC,
            ),
            child: const Icon(
              Icons.ios_share_rounded,
              size: 36,
              color: MerzoxColors.kColorEE6C4D,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'shareApp.heading'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: MerzoxColors.kColor2B2B2B,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'shareApp.body'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: MerzoxColors.kColor707070,
            fontSize: 13,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 26),
        _StoreLinkCard(store: store, busy: busy),
        const SizedBox(height: 28),
        Text(
          'shareApp.chooseMethod'.tr(),
          style: const TextStyle(
            color: MerzoxColors.kColor2B2B2B,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _targetStyles.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisExtent: 72,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final targetStyle = _targetStyles[index];
            return Builder(
              builder: (targetContext) => _ShareTargetButton(
                style: targetStyle,
                loading: busy && state.activeTarget == targetStyle.target,
                onPressed: busy
                    ? null
                    : () => context.read<ShareAppBloc>().add(
                        ShareAppTargetRequested(
                          targetStyle.target,
                          sharePositionOrigin: _originFor(targetContext),
                        ),
                      ),
              ),
            );
          },
        ),
      ],
    );
  }

  Rect? _originFor(BuildContext context) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }
}

class _StoreLinkCard extends StatelessWidget {
  final ShareAppStoreInfo store;
  final bool busy;

  const _StoreLinkCard({required this.store, required this.busy});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MerzoxColors.kColorF5F9FC,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: MerzoxColors.kColorDEEEF8),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: busy
            ? null
            : () =>
                  context.read<ShareAppBloc>().add(const ShareAppStoreOpened()),
        child: SizedBox(
          height: 68,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 6, 8),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                  ),
                  child: Icon(
                    store.isAppleStore
                        ? Icons.apple_rounded
                        : Icons.android_rounded,
                    color: MerzoxColors.kColor3D5A80,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        store.storeName,
                        style: const TextStyle(
                          color: MerzoxColors.kColor2B2B2B,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        store.uri.toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          color: MerzoxColors.kColor767676,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'shareApp.copyLink'.tr(),
                  onPressed: busy
                      ? null
                      : () => context.read<ShareAppBloc>().add(
                          const ShareAppLinkCopied(),
                        ),
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.copy_rounded, size: 20),
                  color: MerzoxColors.kColor3D5A80,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShareTargetButton extends StatelessWidget {
  final _ShareTargetStyle style;
  final bool loading;
  final VoidCallback? onPressed;

  const _ShareTargetButton({
    required this.style,
    required this.loading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: MerzoxColors.kColorE2E2E2),
        borderRadius: BorderRadius.circular(6),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                height: 34,
                child: Center(
                  child: loading
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: style.color,
                          ),
                        )
                      : Icon(style.icon, color: style.color, size: 25),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  style.labelKey.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: MerzoxColors.kColor393939,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class _ShareTargetStyle {
  final ShareAppTarget target;
  final String labelKey;
  final IconData icon;
  final Color color;

  const _ShareTargetStyle({
    required this.target,
    required this.labelKey,
    required this.icon,
    required this.color,
  });
}

const _targetStyles = [
  _ShareTargetStyle(
    target: ShareAppTarget.whatsapp,
    labelKey: 'shareApp.whatsapp',
    icon: Icons.chat_rounded,
    color: Color(0xFF25A85A),
  ),
  _ShareTargetStyle(
    target: ShareAppTarget.messenger,
    labelKey: 'shareApp.messenger',
    icon: Icons.bolt_rounded,
    color: Color(0xFF0084FF),
  ),
  _ShareTargetStyle(
    target: ShareAppTarget.instagram,
    labelKey: 'shareApp.instagram',
    icon: Icons.camera_alt_outlined,
    color: Color(0xFFC13584),
  ),
  _ShareTargetStyle(
    target: ShareAppTarget.telegram,
    labelKey: 'shareApp.telegram',
    icon: Icons.send_rounded,
    color: Color(0xFF229ED9),
  ),
  _ShareTargetStyle(
    target: ShareAppTarget.email,
    labelKey: 'shareApp.email',
    icon: Icons.email_outlined,
    color: MerzoxColors.kColor3D5A80,
  ),
  _ShareTargetStyle(
    target: ShareAppTarget.system,
    labelKey: 'shareApp.more',
    icon: Icons.share_outlined,
    color: MerzoxColors.kColorEE6C4D,
  ),
];
