import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';

import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/constants/money.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart'
    show ProductCardImage;
import 'package:merzox/services/api_service.dart';

/// The shelves, as seen from inside one conversation.
///
/// Which shop they belong to is never asked here: the conversation decides it,
/// server-side. That is what keeps a merchant to their own products and a
/// customer to the products of the shop they are actually talking to, without
/// this screen having to know which of the two is looking.
///
/// A tap does not open the product. It hands it back to the message box,
/// which is the whole point of the screen - the reader came here to point at
/// something, not to read about it.
class ShareProductPage extends StatefulWidget {
  final String conversationId;

  /// Injected by tests, which have no server.
  final ApiService? apiService;
  final AuthSessionService authSessionService;

  const ShareProductPage({
    required this.conversationId,
    this.apiService,
    this.authSessionService = const AuthSessionService(),
    super.key,
  });

  @override
  State<ShareProductPage> createState() => _ShareProductPageState();
}

class _ShareProductPageState extends State<ShareProductPage> {
  late final ApiService _api = widget.apiService ?? ApiService();

  List<BusinessProductApiModel>? _products;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = '');

    try {
      final AuthSessionSnapshot session = await widget.authSessionService
          .read();
      final String? token = session.token;
      if (token == null) throw StateError('Authentication required');

      final List<BusinessProductApiModel> products = await _api
          .conversationProducts(
            token: token,
            conversationId: widget.conversationId,
          );

      if (!mounted) return;
      setState(() => _products = products);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _products = const <BusinessProductApiModel>[];
        _error = localizeApiErrorOrRaw(ApiService.messageFromError(error));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Text(
          'messages.shareProductTitle'.tr(),
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: MerzoxColors.kColor2B2B2B,
          ),
        ),
      ),
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    final List<BusinessProductApiModel>? products = _products;

    if (products == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error.isNotEmpty) {
      return _Notice(text: _error, onRetry: _load);
    }

    if (products.isEmpty) {
      return _Notice(text: 'messages.shareProductEmpty'.tr());
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.82,
      ),
      itemCount: products.length,
      itemBuilder: (BuildContext context, int index) {
        final BusinessProductApiModel product = products[index];

        return _PickableProduct(
          product: product,
          onPick: () => Navigator.of(context).pop(product),
        );
      },
    );
  }
}

/// One product, offered to be pointed at rather than read.
class _PickableProduct extends StatelessWidget {
  final BusinessProductApiModel product;
  final VoidCallback onPick;

  const _PickableProduct({required this.product, required this.onPick});

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
        key: ValueKey<String>('shareProduct.${product.id}'),
        onTap: onPick,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(child: ProductCardImage(imageUrl: product.imageUrl)),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      product.name,
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
                    '₪ ${merzoxAmount(product.displayPrice)}',
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
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;
  final VoidCallback? onRetry;

  const _Notice({required this.text, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: MerzoxColors.kColor8D99AE,
              ),
            ),
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: onRetry,
                child: Text('common.retry'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
