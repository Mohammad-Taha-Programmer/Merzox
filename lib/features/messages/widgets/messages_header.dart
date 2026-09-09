import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/colors.dart';
import '../../../core/widgets/merzox_back_chevron.dart';
import '../../notifications/widgets/global_notification_bell.dart';
import '../bloc/messages_search_bloc.dart';
import '../bloc/messages_search_event.dart';
import '../bloc/messages_search_state.dart';
import 'messages_search_icon.dart';

/// The bar over the inbox: a way back, the screen's name, and a way to search.
///
/// The artboard puts the chevron at the reading edge and the magnifier at the
/// far one. The far one is also where the notification bell floats, so the
/// magnifier stands inboard of it by the width every other top bar reserves -
/// the bell is above the router and cannot be moved per screen.
const double kMessagesHeaderHeight = 44;

/// The tap target around each 24-square mark.
const double kMessagesHeaderTouchTarget = 40;

class MessagesHeader extends StatefulWidget {
  final String title;

  /// Whether there is anywhere to go back to. The merchant reaches the inbox
  /// from their profile; the customer's is a tab and has no exit.
  final bool showBack;

  const MessagesHeader({required this.title, this.showBack = false, super.key});

  @override
  State<MessagesHeader> createState() => _MessagesHeaderState();
}

class _MessagesHeaderState extends State<MessagesHeader> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _open() {
    context.read<MessagesSearchBloc>().add(const MessagesSearchOpened());
    // The box is useless without the keyboard, and asking the reader to tap it
    // a second time to type in the field they just opened is a wasted step.
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  void _close() {
    _controller.clear();
    _focus.unfocus();
    context.read<MessagesSearchBloc>().add(const MessagesSearchClosed());
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<MessagesSearchBloc, MessagesSearchState>(
      builder: (BuildContext context, MessagesSearchState state) {
        return SizedBox(
          height: kMessagesHeaderHeight,
          width: double.infinity,
          child: state.open ? _field(context) : _bar(context),
        );
      },
    );
  }

  Widget _bar(BuildContext context) {
    return Stack(
      children: <Widget>[
        Center(
          child: Text(
            widget.title,
            style: const TextStyle(
              color: MerzoxColors.kColor2B2B2B,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        if (widget.showBack)
          PositionedDirectional(
            start: 8,
            top: 2,
            child: _HeaderButton(
              semanticsLabel: 'common.back'.tr(),
              valueKey: 'merzox.messages.back',
              onTap: () => Navigator.of(context).maybePop(),
              child: const MerzoxBackChevron(),
            ),
          ),
        PositionedDirectional(
          // Clear of the notification bell, which floats over this corner on
          // every screen.
          end: kGlobalBellReservedWidth + 8,
          top: 2,
          child: _HeaderButton(
            semanticsLabel: 'messages.searchOpen'.tr(),
            valueKey: 'merzox.messages.searchOpen',
            onTap: _open,
            child: const MessagesSearchIcon(),
          ),
        ),
      ],
    );
  }

  Widget _field(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        8,
        2,
        kGlobalBellReservedWidth + 4,
        2,
      ),
      child: Row(
        children: <Widget>[
          _HeaderButton(
            semanticsLabel: 'messages.searchClose'.tr(),
            valueKey: 'merzox.messages.searchClose',
            onTap: _close,
            child: const Icon(
              Icons.close_rounded,
              size: 20,
              color: MerzoxColors.kColor353535,
            ),
          ),
          Expanded(
            child: TextField(
              key: const ValueKey<String>('merzox.messages.searchField'),
              controller: _controller,
              focusNode: _focus,
              textInputAction: TextInputAction.search,
              onChanged: (String value) => context
                  .read<MessagesSearchBloc>()
                  .add(MessagesSearchQueryChanged(value)),
              // The keyboard's own search key does not wait for the debounce.
              onSubmitted: (String value) => context
                  .read<MessagesSearchBloc>()
                  .add(MessagesSearchSubmitted(value)),
              style: const TextStyle(
                fontSize: 14,
                color: MerzoxColors.kColor2B2B2B,
              ),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: 'messages.searchHint'.tr(),
                hintStyle: const TextStyle(
                  fontSize: 13,
                  color: MerzoxColors.kColor9F9F9F,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          const MessagesSearchIcon(size: 20),
        ],
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  final String semanticsLabel;
  final String valueKey;

  const _HeaderButton({
    required this.child,
    required this.onTap,
    required this.semanticsLabel,
    required this.valueKey,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: InkWell(
        key: ValueKey<String>(valueKey),
        onTap: onTap,
        borderRadius: BorderRadius.circular(kMessagesHeaderTouchTarget / 2),
        child: SizedBox(
          width: kMessagesHeaderTouchTarget,
          height: kMessagesHeaderTouchTarget,
          child: Center(child: child),
        ),
      ),
    );
  }
}
