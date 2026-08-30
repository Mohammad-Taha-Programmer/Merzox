import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/constants/money.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_event.dart';
import 'package:merzox/features/cart/bloc/cart_state.dart';
import 'package:merzox/features/checkout/widgets/checkout_step_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The two customer-facing checkout steps the corpus draws.
///
/// SCOPE, stated plainly. This screen collects and confirms; it does not change
/// how an order is placed. Confirming dispatches the same `CartCheckoutRequested`
/// the cart already used, so every guarantee the checkout backend was hardened
/// for - server-derived pricing, the reservation fence, the monotonic
/// finalize/release decision - applies unchanged.
///
/// Two things the artboards show are NOT built, because the system has no truth
/// behind them and drawing them would be a lie:
///
///   * `تفاصيل المتجر – 16` offers a LIST of previously used addresses. A user
///     document holds a single `address` string, so this step shows that one
///     address and lets the customer replace it.
///   * `تفاصيل المتجر – 24` offers two delivery speeds at ₪10 and ₪30. The
///     server computes one flat fee (`deliveryFeeFor`), and the fee shown to a
///     customer must be the fee the server will charge, so only that one is
///     offered.
///
/// Both need backend work before their UI can be honest.
class CheckoutPage extends StatefulWidget {
  /// Where a completed checkout returns to.
  final VoidCallback? onCompleted;

  const CheckoutPage({super.key, this.onCompleted});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  CheckoutStep _step = CheckoutStep.buyerDetails;

  void _back() {
    if (_step == CheckoutStep.payment) {
      setState(() => _step = CheckoutStep.buyerDetails);
      return;
    }
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: BlocConsumer<CartBloc, CartState>(
          listenWhen: (CartState previous, CartState current) =>
              previous.messageCode != current.messageCode &&
              current.messageCode.isNotEmpty,
          listener: (BuildContext context, CartState state) {
            // The cart clears itself on success, so a placed order is an empty
            // cart plus its message. Leaving the customer on a stale review
            // screen would invite a second submission.
            if (state.items.isEmpty) widget.onCompleted?.call();
          },
          builder: (BuildContext context, CartState state) {
            return Column(
              children: <Widget>[
                _CheckoutHeader(step: _step, onBack: _back),
                const SizedBox(height: 14),
                CheckoutStepIndicator(current: _step),
                const SizedBox(height: 26),
                Expanded(
                  child: _step == CheckoutStep.buyerDetails
                      ? _BuyerDetailsStep(
                          onContinue: () =>
                              setState(() => _step = CheckoutStep.payment),
                        )
                      : _PaymentStep(state: state),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CheckoutHeader extends StatelessWidget {
  final CheckoutStep step;
  final VoidCallback onBack;

  const _CheckoutHeader({required this.step, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 53,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Text(
            step == CheckoutStep.buyerDetails
                ? 'checkout.buyerTitle'.tr()
                : 'checkout.paymentTitle'.tr(),
            style: const TextStyle(
              color: MerzoxColors.kColor2B2B2B,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          PositionedDirectional(
            start: 8,
            child: IconButton(
              tooltip: 'common.back'.tr(),
              onPressed: onBack,
              icon: const Icon(
                Icons.chevron_right_rounded,
                color: MerzoxColors.kColor5E5E5E,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1 - who is buying, and where it goes.
// ---------------------------------------------------------------------------

class _BuyerDetailsStep extends StatefulWidget {
  final VoidCallback onContinue;

  const _BuyerDetailsStep({required this.onContinue});

  @override
  State<_BuyerDetailsStep> createState() => _BuyerDetailsStepState();
}

class _BuyerDetailsStepState extends State<_BuyerDetailsStep> {
  String _address = '';
  String _name = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Reads the delivery identity from the same place the checkout submission
  /// reads it, so the address confirmed here is the address that is sent.
  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _address = prefs.getString(AuthBloc.addressKey)?.trim() ?? '';
      _name = prefs.getString(AuthBloc.nameKey)?.trim() ?? '';
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final String address = _address;
    final bool hasAddress = address.isNotEmpty;

    return Builder(
      builder: (BuildContext context) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: <Widget>[
            Text(
              'checkout.savedAddress'.tr(),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: MerzoxColors.kColor2B2B2B,
              ),
            ),
            const SizedBox(height: 12),
            if (hasAddress)
              _AddressCard(address: address, name: _name)
            else
              // Honest rather than empty: there is nothing to select yet.
              Text(
                'checkout.noSavedAddress'.tr(),
                style: TextStyle(
                  fontSize: 12,
                  color: MerzoxColors.kColor767676,
                ),
              ),
            const SizedBox(height: 18),
            _AddAddressButton(onPressed: () => context.push('/profile/edit')),
            const SizedBox(height: 26),
            FilledButton(
              onPressed: hasAddress ? widget.onContinue : null,
              style: FilledButton.styleFrom(
                backgroundColor: MerzoxColors.kColor3D5A80,
                minimumSize: const Size.fromHeight(47),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: Text(
                'checkout.continue'.tr(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _AddressCard extends StatelessWidget {
  final String address;
  final String name;

  const _AddressCard({required this.address, required this.name});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: MerzoxColors.kColorB9DDF3),
      ),
      child: Row(
        children: <Widget>[
          // The only address there is, so it is the selected one. It is a
          // radio and not a checkbox because the artboard's list is a choice -
          // this build simply has one entry to choose from.
          const Icon(
            Icons.radio_button_checked,
            size: 20,
            color: MerzoxColors.kColor3D5A80,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  name.isEmpty ? address : '$name، $address',
                  textAlign: TextAlign.end,
                  style: const TextStyle(
                    fontSize: 13,
                    color: MerzoxColors.kColor2B2B2B,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AddAddressButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _AddAddressButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: MerzoxColors.kColorEE6C4D,
        minimumSize: const Size.fromHeight(47),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          const Icon(Icons.add_circle_outline_rounded, size: 22),
          Text(
            'checkout.addAddress'.tr(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 22),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 - what is being bought, and what it costs.
// ---------------------------------------------------------------------------

class _PaymentStep extends StatelessWidget {
  final CartState state;

  const _PaymentStep({required this.state});

  @override
  Widget build(BuildContext context) {
    final bool busy = state.status == CartStatus.checkingOut;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: <Widget>[
        for (final CartItem item in state.items) ...<Widget>[
          _CheckoutLine(item: item),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 8),
        _SectionLabel(text: 'checkout.paymentTitle'.tr()),
        const SizedBox(height: 8),
        // Cash on delivery is the whole list, in the artboard and in the
        // backend alike: every other method is recognised for history and
        // refused with PAYMENT_METHOD_UNAVAILABLE. Offering one would be
        // offering something the server will not accept.
        const _SelectedOption(labelKey: 'checkout.cashOnDelivery'),
        const SizedBox(height: 18),
        _SectionLabel(text: 'checkout.delivery'.tr()),
        const SizedBox(height: 8),
        // No fee is printed here. `deliveryFeeFor` is a SERVER rule, and a
        // number computed in the client is a number the server never agreed
        // to - which is the class of defect the checkout hardening removed.
        const _SelectedOption(labelKey: 'checkout.standardDelivery'),
        const SizedBox(height: 22),
        const Divider(height: 1),
        const SizedBox(height: 16),
        _SectionLabel(text: 'checkout.invoice'.tr()),
        const SizedBox(height: 10),
        _InvoiceRow(
          label: 'home.cart.subtotal'.tr(),
          value: '₪ ${merzoxAmount(state.subtotal)}',
        ),
        const SizedBox(height: 8),
        _InvoiceRow(
          label: 'orders.delivery'.tr(),
          value: 'home.cart.deliveryCalculatedLater'.tr(),
        ),
        const SizedBox(height: 8),
        _InvoiceRow(
          // Stated as the relationship, not as an invented figure: the total
          // is the subtotal plus a fee only the server can compute.
          label: 'home.cart.total'.tr(),
          value: 'checkout.totalPending'.tr(
            args: <String>['₪ ${merzoxAmount(state.subtotal)}'],
          ),
          strong: true,
        ),
        const SizedBox(height: 24),
        _CheckoutActions(busy: busy),
      ],
    );
  }
}

class _CheckoutLine extends StatelessWidget {
  final CartItem item;

  const _CheckoutLine({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF9F9F9,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: MerzoxColors.kColor2B2B2B,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${'checkout.unitPrice'.tr()} ${merzoxAmount(item.price)}'
                  '   ${'home.cart.quantity'.tr(args: <String>['${item.quantity}'])}',
                  style: TextStyle(
                    fontSize: 11,
                    color: MerzoxColors.kColor767676,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(4),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.shopping_bag_outlined,
              color: MerzoxColors.kColor3D5A80,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;

  const _SectionLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: MerzoxColors.kColor2B2B2B,
        ),
      ),
    );
  }
}

/// An option that is selected because it is the only one the system supports.
///
/// Drawn as a chosen radio rather than as plain text so the screen still reads
/// as the artboard's choice, and so a second option can join it without the
/// layout changing.
class _SelectedOption extends StatelessWidget {
  final String labelKey;

  const _SelectedOption({required this.labelKey});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(
          Icons.radio_button_checked,
          size: 20,
          color: MerzoxColors.kColor3D5A80,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            labelKey.tr(),
            style: const TextStyle(
              fontSize: 13,
              color: MerzoxColors.kColor2B2B2B,
            ),
          ),
        ),
      ],
    );
  }
}

class _InvoiceRow extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _InvoiceRow({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      fontSize: strong ? 14 : 13,
      fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
      color: strong ? MerzoxColors.kColor2B2B2B : MerzoxColors.kColor767676,
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: <Widget>[
        Text(label, style: style),
        Text(value, style: style),
      ],
    );
  }
}

class _CheckoutActions extends StatelessWidget {
  final bool busy;

  const _CheckoutActions({required this.busy});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: busy
                    ? null
                    : () => context.read<CartBloc>().add(
                        const CartCheckoutRequested(),
                      ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: MerzoxColors.kColor2B2B2B,
                  side: BorderSide(color: MerzoxColors.kColorEE6C4D),
                  minimumSize: const Size.fromHeight(47),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        'checkout.confirm'.tr(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : () => context.pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: MerzoxColors.kColorEE6C4D,
                  minimumSize: const Size.fromHeight(47),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: Text(
                  'checkout.cancel'.tr(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: MerzoxColors.kColor767676,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'checkout.cancellationWindow'.tr(),
                style: TextStyle(
                  fontSize: 11,
                  color: MerzoxColors.kColor767676,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
