import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/constants/money.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart'
    show ProductCardImage;
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/product_details/pages/product_details_page.dart';
import 'package:merzox/services/api_service.dart';

/// How wide a shared product sits inside a bubble.
///
/// Narrower than the bubble's own 72% of the screen: a card is an object in
/// the thread rather than a paragraph, and one that filled the width would
/// read as a screen rather than as something somebody sent.
const double kSharedProductCardWidth = 168;

/// How tall its picture is.
const double kSharedProductImageHeight = 118;

/// A product shared into a conversation.
///
/// Drawn the way a shop's own card is drawn - white, a hairline border, the
/// picture above the words - with everything the card in a catalogue carries
/// for browsing taken out. What is left is what a person points at: the
/// picture, the name, the price. Rating, favourite and add-to-cart belong to
/// the product page this leads to.
class SharedProductCard extends StatelessWidget {
  final String name;
  final double price;
  final String imageUrl;

  /// How tall the picture is. The composer draws the same card smaller while
  /// it is still being written, so the keyboard leaves room for the words.
  final double imageHeight;

  /// Opens the product. Supplied so a test can watch without a server, and
  /// null while the card is only a preview of what is about to be sent.
  final VoidCallback? onTap;

  const SharedProductCard({
    required this.name,
    required this.price,
    required this.imageUrl,
    this.imageHeight = kSharedProductImageHeight,
    this.onTap,
    super.key,
  });

  /// The card as a message carries it.
  SharedProductCard.shared({
    required SharedProductApiModel product,
    this.imageHeight = kSharedProductImageHeight,
    this.onTap,
    super.key,
  }) : name = product.name,
       price = product.price,
       imageUrl = product.imageUrl;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: const BorderSide(color: MerzoxColors.kColorEFEFEF),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey<String>('chat.sharedProduct'),
        onTap: onTap,
        child: SizedBox(
          width: kSharedProductCardWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              SizedBox(
                height: imageHeight,
                child: ProductCardImage(imageUrl: imageUrl),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: MerzoxColors.kColor2B2B2B,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '₪ ${merzoxAmount(price)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: MerzoxColors.kColor2B2B2B,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether the reader of a shared card is the shop that sells it.
///
/// Only one shop's products can be shared into a conversation - the shop the
/// conversation is with - so a reader who is on the merchant side of the app
/// is necessarily that shop. There is nothing else to compare: a merchant who
/// wants to buy from another shop turns to the customer side first, and is a
/// customer here like any other.
bool viewerOwnsSharedProduct(AuthSessionSnapshot session) => session.isBusiness;

/// Opens the product a card stands for.
///
/// The card carries a copy taken when it was shared, so the page is not built
/// from it: the shop and the product are read fresh, and what opens is the
/// same page every other route to a product opens, with today's price and
/// today's stock. A product that has since been withdrawn says so rather than
/// opening an empty page.
///
/// Whether the reader owns what they are opening is settled here rather than
/// asked of the server. Only one shop's products can be shared into a
/// conversation - its own - so a reader who is on the merchant side of the
/// app is that shop, and the page freezes the stepper, the cart and the buy
/// button for them. A customer, on either kind of account, gets all of it.
Future<void> openSharedProduct(
  BuildContext context,
  SharedProductApiModel shared, {
  ApiService? apiService,
  AuthSessionService authSessionService = const AuthSessionService(),
}) async {
  final ApiService api = apiService ?? ApiService();
  final NavigatorState navigator = Navigator.of(context);
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);

  try {
    final AuthSessionSnapshot session = await authSessionService.read();
    final List<Object> both = await Future.wait<Object>(<Future<Object>>[
      api.business(businessId: shared.businessId),
      api.businessProduct(
        businessId: shared.businessId,
        productId: shared.productId,
      ),
    ]);

    final BusinessDetailApiModel business = both[0] as BusinessDetailApiModel;
    final BusinessProductApiModel product = both[1] as BusinessProductApiModel;

    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailsPage(
          business: HomeBusiness.fromDetail(business),
          product: product,
          viewerOwnsProduct: viewerOwnsSharedProduct(session),
        ),
      ),
    );
  } catch (_) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text('apiErrors.sharedProductUnavailable'.tr())),
      );
  }
}
