import 'dart:ui' show ImageFilter;

import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:merzox/core/constants/colors.dart';

import '../presentation/bloc/home_state_.dart';

/// The promotional carousel at the top of the customer home screen.
///
/// `الرئيسية` draws a 293x110 card inset 17 from the trailing edge with the
/// next card peeking 49 wide past the leading one, page dots beneath it, and a
/// frosted "buy now" chip laid over the artwork.
///
/// It is driven by the businesses the catalogue already marks as discounted:
/// the artboard's card is a sale promotion ("SALE 50%"), which is exactly what
/// that list holds. No promotions service is invented for it, and when nothing
/// is discounted the carousel is simply absent rather than showing an empty
/// frame.
class HomePromoCarousel extends StatefulWidget {
  final List<HomeBusiness> businesses;
  final void Function(HomeBusiness business) onOpen;

  const HomePromoCarousel({
    super.key,
    required this.businesses,
    required this.onOpen,
  });

  /// Card box, measured from the artboard.
  static const double cardWidth = 293;
  static const double cardHeight = 110;
  static const double cardGap = 16;

  /// The chip sits 15 in from the card's leading edge and 60 down.
  static const double chipWidth = 98;
  static const double chipHeight = 35;
  static const double chipInsetStart = 15;
  static const double chipInsetTop = 60;

  /// Dots band: the artboard puts them 8 under the card.
  static const double dotsGap = 8;
  static const double dotsHeight = 7;

  static const double height = cardHeight + dotsGap + dotsHeight;

  @override
  State<HomePromoCarousel> createState() => _HomePromoCarouselState();
}

class _HomePromoCarouselState extends State<HomePromoCarousel> {
  late final PageController _controller = PageController(
    // 293 of card plus 16 of gap out of a 375 artboard: what is left over is
    // the next card peeking, which is what the artboard shows.
    viewportFraction:
        (HomePromoCarousel.cardWidth + HomePromoCarousel.cardGap) / 375,
  );

  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<HomeBusiness> businesses = widget.businesses;
    if (businesses.isEmpty) return const SizedBox.shrink();

    return Column(
      children: <Widget>[
        SizedBox(
          height: HomePromoCarousel.cardHeight,
          child: PageView.builder(
            controller: _controller,
            padEnds: false,
            onPageChanged: (int page) => setState(() => _page = page),
            itemCount: businesses.length,
            itemBuilder: (_, int index) => Padding(
              padding: const EdgeInsetsDirectional.only(
                start: HomePromoCarousel.cardGap,
              ),
              child: _PromoCard(
                business: businesses[index],
                onTap: () => widget.onOpen(businesses[index]),
              ),
            ),
          ),
        ),
        const SizedBox(height: HomePromoCarousel.dotsGap),
        _Dots(count: businesses.length, active: _page),
      ],
    );
  }
}

class _PromoCard extends StatelessWidget {
  final HomeBusiness business;
  final VoidCallback onTap;

  const _PromoCard({required this.business, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: <Widget>[
            // The catalogue carries no artwork for a business, only the
            // deterministic colour the cards below already use, so the card is
            // that colour rather than a placeholder photograph.
            Positioned.fill(
              child: ColoredBox(color: Color(business.colorValue)),
            ),
            if (business.discount case final String discount)
              PositionedDirectional(
                top: 14,
                end: 18,
                child: Text(
                  discount,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: MerzoxColors.kColorEE6C4D,
                  ),
                ),
              ),
            PositionedDirectional(
              start: HomePromoCarousel.chipInsetStart,
              top: HomePromoCarousel.chipInsetTop,
              child: _BuyNowChip(backdrop: Color(business.colorValue)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The artboard's frosted chip: it blurs and lifts the artwork behind it
/// rather than sitting on a flat panel, which is what the XD node asks for.
class _BuyNowChip extends StatelessWidget {
  /// What the chip sits on, which decides whether its label can be white.
  final Color backdrop;

  const _BuyNowChip({required this.backdrop});

  @override
  Widget build(BuildContext context) {
    final bool onDark = backdrop.computeLuminance() < 0.5;

    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
        child: Container(
          width: HomePromoCarousel.chipWidth,
          height: HomePromoCarousel.chipHeight,
          alignment: Alignment.center,
          // The XD node's own fill is fully transparent; the lift comes from
          // the filter's brightness, which is a white wash at this opacity.
          color: Colors.white.withValues(alpha: 0.15),
          child: Text(
            'home.buyNow'.tr(),
            style: TextStyle(
              fontSize: 13,
              color: onDark ? Colors.white : MerzoxColors.kColor2B2B2B,
            ),
          ),
        ),
      ),
    );
  }
}

class _Dots extends StatelessWidget {
  final int count;
  final int active;

  const _Dots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (int index = 0; index < count; index++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Container(
              width: index == active ? 7 : 5,
              height: index == active ? 7 : 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: index == active
                    ? MerzoxColors.kColorEE6C4D
                    : MerzoxColors.kColorD8D8D8,
              ),
            ),
          ),
      ],
    );
  }
}
