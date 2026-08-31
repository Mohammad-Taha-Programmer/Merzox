import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/auth/secure_token_store.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/constants/money.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_event.dart';
import 'package:merzox/features/cart/bloc/cart_state.dart';
import 'package:merzox/features/checkout/pages/address_form_page.dart';
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

  /// Reads the delivery tiers. Injectable so a test can serve them without a
  /// network, which is also the only way a golden can render them at all.
  final ApiService? apiService;

  const CheckoutPage({super.key, this.onCompleted, this.apiService});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  CheckoutStep _step = CheckoutStep.buyerDetails;

  /// The tiers the server charges, and which one the buyer picked.
  ///
  /// Null until the request answers. Nothing is invented in the meantime: the
  /// screen says the fee is still being fetched rather than guessing it.
  DeliveryOptionsApiResponse? _delivery;
  String _deliveryOption = 'standard';

  /// The address the buyer step settled on, which is the one the order takes.
  String _deliveryAddress = '';

  @override
  void initState() {
    super.initState();
    _loadDeliveryOptions();
  }

  Future<void> _loadDeliveryOptions() async {
    try {
      final DeliveryOptionsApiResponse options =
          await (widget.apiService ?? ApiService()).deliveryOptions();
      if (!mounted) return;

      setState(() {
        _delivery = options;
        _deliveryOption = options.defaultOption;
      });
    } catch (_) {
      // A tier list that did not arrive leaves the screen on its default,
      // which is the tier the server charges when none is named.
    }
  }

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
            // The cart clears itself on success, so a placed order is an
            // empty cart plus its message. Moving to the confirmation both
            // shows the customer their order number and takes the review
            // screen away, so there is nothing left to submit twice.
            if (state.items.isEmpty) {
              setState(() => _step = CheckoutStep.confirmed);
            }
          },
          builder: (BuildContext context, CartState state) {
            return Column(
              children: <Widget>[
                _CheckoutHeader(step: _step, onBack: _back),
                const SizedBox(height: 14),
                CheckoutStepIndicator(current: _step),
                const SizedBox(height: 26),
                Expanded(
                  child: switch (_step) {
                    CheckoutStep.buyerDetails => _BuyerDetailsStep(
                      apiService: widget.apiService,
                      onContinue: () =>
                          setState(() => _step = CheckoutStep.payment),
                      onAddressChanged: (String line) =>
                          _deliveryAddress = line,
                    ),
                    CheckoutStep.payment => _PaymentStep(
                      state: state,
                      delivery: _delivery,
                      selectedOption: _deliveryOption,
                      deliveryAddress: _deliveryAddress,
                      onOptionChanged: (String option) =>
                          setState(() => _deliveryOption = option),
                    ),
                    CheckoutStep.confirmed => _ConfirmedStep(
                      orderIds: state.placedOrderIds,
                      onDone: widget.onCompleted,
                    ),
                  },
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
            switch (step) {
              CheckoutStep.buyerDetails => 'checkout.buyerTitle'.tr(),
              CheckoutStep.payment => 'checkout.paymentTitle'.tr(),
              CheckoutStep.confirmed => 'checkout.doneTitle'.tr(),
            },
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

  /// Reports what the order should record, so the page can send it.
  final ValueChanged<String> onAddressChanged;

  final ApiService? apiService;

  const _BuyerDetailsStep({
    required this.onContinue,
    required this.onAddressChanged,
    this.apiService,
  });

  @override
  State<_BuyerDetailsStep> createState() => _BuyerDetailsStepState();
}

class _BuyerDetailsStepState extends State<_BuyerDetailsStep> {
  List<SavedAddressApiModel> _addresses = const <SavedAddressApiModel>[];

  /// The profile's single free-text address, shown when the book is empty so
  /// an account that predates the book can still check out.
  String _legacyAddress = '';
  String _name = '';
  String _token = '';
  bool _loaded = false;

  ApiService get _api => widget.apiService ?? ApiService();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String token = await const SecureTokenStore().read() ?? '';
    final String legacy = prefs.getString(AuthBloc.addressKey)?.trim() ?? '';
    final String name = prefs.getString(AuthBloc.nameKey)?.trim() ?? '';

    List<SavedAddressApiModel> addresses = const <SavedAddressApiModel>[];
    if (token.isNotEmpty) {
      try {
        addresses = await _api.myAddresses(token: token);
      } catch (_) {
        // An unreachable book falls back to the profile address rather than
        // blocking checkout on a list that is only a convenience.
      }
    }

    if (!mounted) return;
    setState(() {
      _addresses = addresses;
      _legacyAddress = legacy;
      _name = name;
      _token = token;
      _loaded = true;
      _selected ??= _defaultId(addresses);
    });
    widget.onAddressChanged(_selectedLine);
  }

  String? _selected;

  static String? _defaultId(List<SavedAddressApiModel> addresses) {
    for (final SavedAddressApiModel entry in addresses) {
      if (entry.isDefault) return entry.id;
    }

    return addresses.isEmpty ? null : addresses.first.id;
  }

  SavedAddressApiModel? get _selectedAddress {
    for (final SavedAddressApiModel entry in _addresses) {
      if (entry.id == _selected) return entry;
    }

    return null;
  }

  /// What the order will record, which is what the step must be showing.
  String get _selectedLine =>
      _selectedAddress?.line ?? (_addresses.isEmpty ? _legacyAddress : '');

  Future<void> _addAddress() async {
    if (_token.isEmpty) return;

    final List<SavedAddressApiModel>? updated = await Navigator.of(context)
        .push<List<SavedAddressApiModel>>(
          MaterialPageRoute<List<SavedAddressApiModel>>(
            builder: (_) =>
                AddressFormPage(token: _token, apiService: widget.apiService),
          ),
        );
    if (updated == null || !mounted) return;

    setState(() {
      _addresses = updated;
      _selected = _defaultId(updated);
    });
    widget.onAddressChanged(_selectedLine);
  }

  void _select(String id) {
    setState(() => _selected = id);
    widget.onAddressChanged(_selectedLine);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(child: CircularProgressIndicator());
    }

    final bool canContinue = _selectedLine.isNotEmpty;

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
        if (_addresses.isNotEmpty)
          for (final SavedAddressApiModel entry in _addresses)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AddressCard(
                address: entry.line,
                name: entry.fullName,
                phone: entry.phone,
                selected: entry.id == _selected,
                onSelected: () => _select(entry.id),
              ),
            )
        else if (_legacyAddress.isNotEmpty)
          _AddressCard(
            address: _legacyAddress,
            name: _name,
            phone: '',
            selected: true,
            onSelected: null,
          )
        else
          // Honest rather than empty: there is nothing to select yet.
          Text(
            'checkout.noSavedAddress'.tr(),
            style: TextStyle(fontSize: 12, color: MerzoxColors.kColor767676),
          ),
        const SizedBox(height: 18),
        _AddAddressButton(onPressed: _addAddress),
        const SizedBox(height: 26),
        FilledButton(
          onPressed: canContinue ? widget.onContinue : null,
          style: FilledButton.styleFrom(
            backgroundColor: MerzoxColors.kColor3D5A80,
            minimumSize: const Size.fromHeight(47),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          child: Text(
            'checkout.continue'.tr(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

class _AddressCard extends StatelessWidget {
  final String address;
  final String name;

  /// The artboard puts the phone under the name; a delivery address without
  /// one is an address a driver cannot use.
  final String phone;

  final bool selected;
  final VoidCallback? onSelected;

  const _AddressCard({
    required this.address,
    required this.name,
    required this.phone,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelected,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: MerzoxColors.kColorB9DDF3),
        ),
        child: Row(
          children: <Widget>[
            // A radio and not a checkbox: the artboard's list is a choice of
            // one, and an order goes to exactly one address.
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected
                  ? MerzoxColors.kColor3D5A80
                  : MerzoxColors.kColorBEBEBE,
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
                  if (phone.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      phone,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 12,
                        color: MerzoxColors.kColor767676,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
  final DeliveryOptionsApiResponse? delivery;
  final String selectedOption;
  final String deliveryAddress;
  final ValueChanged<String> onOptionChanged;

  const _PaymentStep({
    required this.state,
    required this.delivery,
    required this.selectedOption,
    required this.deliveryAddress,
    required this.onOptionChanged,
  });

  /// The fee the server charges for the picked tier, or null while unknown.
  double? get _fee => delivery?.feeFor(selectedOption);

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
        // Every figure below came from the server. The screen picks a tier by
        // name and prints the price it was sent; it never computes one, which
        // is the class of defect the checkout hardening removed.
        if (delivery == null)
          const _SelectedOption(labelKey: 'checkout.standardDelivery')
        else
          for (final DeliveryOptionApiModel option in delivery!.options)
            _DeliveryChoice(
              option: option,
              selected: option.option == selectedOption,
              onSelected: () => onOptionChanged(option.option),
            ),
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
          value: _fee == null
              ? 'home.cart.deliveryCalculatedLater'.tr()
              : '₪ ${merzoxAmount(_fee!)}',
        ),
        const SizedBox(height: 8),
        _InvoiceRow(
          // With the fee known the total is stated; without it, stated as the
          // relationship rather than as an invented figure.
          label: 'home.cart.total'.tr(),
          value: _fee == null
              ? 'checkout.totalPending'.tr(
                  args: <String>['₪ ${merzoxAmount(state.subtotal)}'],
                )
              : '₪ ${merzoxAmount(state.subtotal + _fee!)}',
          strong: true,
        ),
        const SizedBox(height: 24),
        _CheckoutActions(
          busy: busy,
          deliveryOption: selectedOption,
          deliveryAddress: deliveryAddress,
        ),
      ],
    );
  }
}

/// The confirmation of `تفاصيل المتجر – 17`.
///
/// The artboard draws a courier, a success line, the order number and two ways
/// on: to the customer's orders, or back to the home screen. There is no
/// courier illustration in the asset bundle, so the icon that stands in for it
/// is the same one the order-tracking screen uses for a delivery in progress —
/// borrowed rather than invented.
class _ConfirmedStep extends StatelessWidget {
  final List<String> orderIds;
  final VoidCallback? onDone;

  const _ConfirmedStep({required this.orderIds, this.onDone});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      children: <Widget>[
        const SizedBox(height: 20),
        const Icon(
          Icons.delivery_dining_rounded,
          size: 120,
          color: MerzoxColors.kColor98C1D9,
        ),
        const SizedBox(height: 40),
        Text(
          'checkout.orderPlaced'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
        const SizedBox(height: 12),
        // A basket spanning two stores becomes two orders, and the customer is
        // owed both numbers rather than whichever one happened to be first.
        for (final String id in orderIds)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              'checkout.orderNumber'.tr(args: <String>[id]),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: MerzoxColors.kColor767676,
              ),
            ),
          ),
        const SizedBox(height: 36),
        SizedBox(
          height: 44,
          child: FilledButton(
            onPressed: () {
              onDone?.call();
              context.go('/orders');
            },
            style: FilledButton.styleFrom(
              backgroundColor: MerzoxColors.kColorEE6C4D,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text(
              'checkout.goToOrders'.tr(),
              style: const TextStyle(fontSize: 14, color: Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 44,
          child: OutlinedButton(
            onPressed: () {
              onDone?.call();
              context.go('/home');
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: MerzoxColors.kColor2B2B2B,
              side: const BorderSide(color: MerzoxColors.kColorEE6C4D),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            child: Text(
              'checkout.backHome'.tr(),
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
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

/// One delivery tier, priced by the server and picked by name.
class _DeliveryChoice extends StatelessWidget {
  final DeliveryOptionApiModel option;
  final bool selected;
  final VoidCallback onSelected;

  const _DeliveryChoice({
    required this.option,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelected,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: <Widget>[
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 18,
              color: selected
                  ? MerzoxColors.kColor3D5A80
                  : MerzoxColors.kColorBEBEBE,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '₪ ${merzoxAmount(option.fee)}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: MerzoxColors.kColor2B2B2B,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'checkout.deliveryOptions.${option.option}'.tr(),
                    style: const TextStyle(
                      fontSize: 11,
                      color: MerzoxColors.kColor767676,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckoutActions extends StatefulWidget {
  final bool busy;
  final String deliveryOption;
  final String deliveryAddress;

  const _CheckoutActions({
    required this.busy,
    required this.deliveryOption,
    required this.deliveryAddress,
  });

  @override
  State<_CheckoutActions> createState() => _CheckoutActionsState();
}

class _CheckoutActionsState extends State<_CheckoutActions> {
  /// Whether the customer has reached for cancel at least once.
  ///
  /// `تفاصيل المتجر – 24` is that state: the cancel button fills and the
  /// twenty-four hour window appears beside it. It stays after the question is
  /// answered with no, so the reason not to is still on screen.
  bool _askedToCancel = false;

  /// `تفاصيل المتجر – 30` asks before abandoning, which the button did not.
  Future<void> _confirmAbandon(BuildContext context) async {
    setState(() => _askedToCancel = true);

    final bool? leave = await showDialog<bool>(
      context: context,
      // The board dims the wizard to #9B9B9B over white, which is black at
      // 100/255 - lighter than Material's own barrier.
      barrierColor: const Color(0x64000000),
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        content: Text(
          'checkout.cancelConfirm'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: <Widget>[
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: MerzoxColors.kColorEE6C4D,
              fixedSize: const Size(84, 40),
            ),
            child: Text('common.yes'.tr()),
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            style: OutlinedButton.styleFrom(
              foregroundColor: MerzoxColors.kColor2B2B2B,
              fixedSize: const Size(84, 40),
            ),
            child: Text('common.no'.tr()),
          ),
        ],
      ),
    );

    if ((leave ?? false) && context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        // `تفاصيل المتجر – 26` fills the confirm and outlines the cancel. It
        // was the other way round here, which put the whole weight of the
        // screen on the button that throws the order away.
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton(
                onPressed: widget.busy
                    ? null
                    : () => context.read<CartBloc>().add(
                        CartCheckoutRequested(
                          deliveryOption: widget.deliveryOption,
                          deliveryAddress: widget.deliveryAddress,
                        ),
                      ),
                style: FilledButton.styleFrom(
                  backgroundColor: _askedToCancel
                      ? Colors.white
                      : MerzoxColors.kColorEE6C4D,
                  foregroundColor: _askedToCancel
                      ? MerzoxColors.kColor2B2B2B
                      : Colors.white,
                  side: _askedToCancel
                      ? const BorderSide(color: MerzoxColors.kColorEE6C4D)
                      : BorderSide.none,
                  minimumSize: const Size.fromHeight(47),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                child: widget.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
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
              child: OutlinedButton(
                onPressed: widget.busy ? null : () => _confirmAbandon(context),
                style: OutlinedButton.styleFrom(
                  backgroundColor: _askedToCancel
                      ? MerzoxColors.kColorEE6C4D
                      : Colors.white,
                  foregroundColor: _askedToCancel
                      ? Colors.white
                      : MerzoxColors.kColor2B2B2B,
                  side: const BorderSide(color: MerzoxColors.kColorEE6C4D),
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
        // Only once cancel has been reached for: a rule about undoing an
        // order does not belong on a screen where nothing has been ordered.
        if (_askedToCancel) ...<Widget>[
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
      ],
    );
  }
}
