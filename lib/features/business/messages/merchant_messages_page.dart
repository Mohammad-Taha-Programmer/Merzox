import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/features/messages/bloc/messages_search_bloc.dart';
import 'package:merzox/features/messages/pages/messages_inbox_view.dart';

/// The merchant inbox. It reuses the customer inbox view; the bloc supplied by
/// the route is the only thing that differs.
///
/// The bar over it belongs to that view too, rather than being drawn again
/// here: the search box lives in the bar, and two copies of a bar with a text
/// field in it is two places for the field to go wrong.
class MerchantMessagesPage extends StatelessWidget {
  const MerchantMessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: BlocProvider<MessagesSearchBloc>(
            create: (_) => MessagesSearchBloc(businessAudience: true),
            child: MessagesInboxView(
              title: 'messages.title'.tr(),
              showBack: true,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            ),
          ),
        ),
      ),
    );
  }
}
