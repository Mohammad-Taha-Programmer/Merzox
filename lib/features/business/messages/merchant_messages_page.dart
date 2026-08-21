import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/messages/pages/messages_inbox_view.dart';

/// The merchant inbox. It reuses the customer inbox view; the bloc supplied by
/// the route is the only thing that differs.
class MerchantMessagesPage extends StatelessWidget {
  const MerchantMessagesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                height: 66,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Text(
                      'messages.title'.tr(),
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
              ),
              Expanded(
                child: MessagesInboxView(
                  title: 'messages.title'.tr(),
                  showTitle: false,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
