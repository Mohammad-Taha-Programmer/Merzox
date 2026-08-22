import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/colors.dart';
import '../../authentication/bloc/auth_bloc.dart';
import '../models/business_models.dart';
import '../../orders/order_status_policy.dart';
import '../orders/merchant_order_detail_page.dart';
import '../settings/store_settings_page.dart';
import 'business_bloc.dart';

class BusinessShellPage extends StatelessWidget {
  final VoidCallback onLoggedOut;

  const BusinessShellPage({super.key, required this.onLoggedOut});

  Future<void> _logout() async {
    await AuthBloc.clearStoredSession();
    onLoggedOut();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: BlocConsumer<BusinessBloc, BusinessState>(
        listener: (context, state) {
          if (state.status == BusinessStatus.failure &&
              state.errorMessage != null) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.errorMessage!)));
          }
        },
        builder: (context, state) {
          if (state.status == BusinessStatus.loading &&
              state.business == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (state.business == null) {
            return Scaffold(
              body: _Failure(
                onRetry: () =>
                    context.read<BusinessBloc>().add(const BusinessStarted()),
              ),
            );
          }
          return Scaffold(
            backgroundColor: const Color(0xFFF9FAFC),
            body: SafeArea(
              child: switch (state.selectedTab) {
                0 => _Dashboard(state: state),
                1 => _Orders(state: state),
                3 => _Products(state: state),
                4 => _Profile(state: state, onLogout: _logout),
                _ => _Dashboard(state: state),
              },
            ),
            bottomNavigationBar: _BusinessNavigation(
              selectedIndex: state.selectedTab,
              onChanged: (index) {
                if (index == 2) {
                  _showProductEditor(context);
                } else {
                  context.read<BusinessBloc>().add(BusinessTabChanged(index));
                }
              },
            ),
          );
        },
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const _PageHeader({required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
    child: Row(
      children: [
        CircleAvatar(
          backgroundColor: Colors.white,
          child: Icon(
            Icons.storefront_rounded,
            color: MerzoxColors.kColor3D5A80,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: MerzoxColors.kColor8D99AE,
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'messages.title'.tr(),
          onPressed: () => context.push('/business/messages'),
          icon: const Icon(Icons.chat_bubble_outline_rounded),
        ),
        IconButton(
          tooltip: 'notifications.title'.tr(),
          onPressed: () => context.push('/notifications?audience=business'),
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
    ),
  );
}

class _Dashboard extends StatelessWidget {
  final BusinessState state;
  const _Dashboard({required this.state});

  @override
  Widget build(BuildContext context) {
    final data = state.dashboard;
    return RefreshIndicator(
      onRefresh: () async {
        context.read<BusinessBloc>().add(const BusinessRefreshed());
      },
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _PageHeader(
            title: 'مرحباً، ${state.business!.name}',
            subtitle: 'ملخص نشاط متجرك',
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              readOnly: true,
              decoration: InputDecoration(
                hintText: 'رقم الطلب، اسم المستخدم...',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _Metric(
                    'المبيعات',
                    '${data?.sales.toStringAsFixed(0) ?? '0'} ₪',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _Metric('الطلبات', '${data?.orderCount ?? 0}')),
                const SizedBox(width: 10),
                Expanded(child: _Metric('الزيارات', '${data?.viewCount ?? 0}')),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  'أحدث الطلبات',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.read<BusinessBloc>().add(
                    const BusinessTabChanged(1),
                  ),
                  child: const Text('المزيد'),
                ),
              ],
            ),
          ),
          if (data == null || data.recentOrders.isEmpty)
            const _Empty(message: 'لا توجد طلبات حديثة')
          else
            ...data.recentOrders.map(
              (order) => _OrderTile(order: order, compact: true),
            ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  const _Metric(this.label, this.value);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: MerzoxColors.kColorDEEEF8),
      borderRadius: BorderRadius.circular(7),
    ),
    child: Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: MerzoxColors.kColor767676),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _Orders extends StatelessWidget {
  final BusinessState state;
  const _Orders({required this.state});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const _PageHeader(
        title: 'الطلبات الواردة',
        subtitle: 'تابع حالة طلبات عملائك',
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'current',
              label: Text('الحالية ${state.orderCounts['current'] ?? ''}'),
            ),
            ButtonSegment(
              value: 'completed',
              label: Text('المكتملة ${state.orderCounts['completed'] ?? ''}'),
            ),
            ButtonSegment(
              value: 'cancelled',
              label: Text('الملغاة ${state.orderCounts['cancelled'] ?? ''}'),
            ),
          ],
          selected: {state.orderGroup},
          onSelectionChanged: (selection) => context.read<BusinessBloc>().add(
            BusinessOrderGroupChanged(selection.first),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Expanded(
        child: RefreshIndicator(
          onRefresh: () async =>
              context.read<BusinessBloc>().add(const BusinessRefreshed()),
          child: state.orders.isEmpty
              ? ListView(
                  children: const [
                    _Empty(message: 'لا توجد طلبات في هذه القائمة'),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: state.orders.length,
                  itemBuilder: (_, index) => _OrderTile(
                    order: state.orders[index],
                    onOpen: () =>
                        _openOrderDetail(context, state, state.orders[index]),
                  ),
                ),
        ),
      ),
    ],
  );
}

/// Opens the merchant order screen, wiring its actions back to the shell's
/// bloc so a status change refreshes the list the user returns to.
void _openOrderDetail(
  BuildContext context,
  BusinessState state,
  OwnerOrder order,
) {
  final bloc = context.read<BusinessBloc>();

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: BlocBuilder<BusinessBloc, BusinessState>(
          builder: (innerContext, innerState) {
            final current = innerState.orders
                .where((candidate) => candidate.id == order.id)
                .firstOrNull;

            return MerchantOrderDetailPage(
              order: current ?? order,
              businessName: innerState.business?.name ?? '',
              businessAddress: innerState.business?.address ?? '',
              isSaving: innerState.status == BusinessStatus.saving,
              onStatusSelected: (status) =>
                  bloc.add(BusinessOrderStatusChanged(order.id, status)),
              onCourierAssigned: (name, phone) async => bloc.add(
                BusinessOrderCourierAssigned(
                  orderId: order.id,
                  name: name,
                  phone: phone,
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}

class _OrderTile extends StatelessWidget {
  final OwnerOrder order;
  final bool compact;
  final VoidCallback? onOpen;
  const _OrderTile({required this.order, this.compact = false, this.onOpen});

  @override
  Widget build(BuildContext context) {
    final currentStatus = OrderStatusPolicy.isStatus(order.status)
        ? order.status
        : 'pending';
    final options = <String>[
      currentStatus,
      ...OrderStatusPolicy.merchantTransitionsFrom(currentStatus),
    ];

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 7),
      color: Colors.white,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(13),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: MerzoxColors.kColorDEEEF8,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.receipt_long_outlined),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // AC-28: an absent customer name is stated as unavailable
                    // rather than filled with an invented identity - a merchant
                    // must never read a placeholder as the customer's name.
                    Text(
                      order.customerName.isEmpty
                          ? 'merchantOrder.customerNameUnavailable'.tr()
                          : order.customerName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontStyle: order.customerName.isEmpty
                            ? FontStyle.italic
                            : FontStyle.normal,
                        color: order.customerName.isEmpty
                            ? MerzoxColors.kColor8D99AE
                            : null,
                      ),
                    ),
                    Text(
                      '#${order.publicId}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    Text(
                      '${order.items.length} منتجات • ${order.total.toStringAsFixed(0)} ₪',
                      style: TextStyle(
                        fontSize: 12,
                        color: MerzoxColors.kColor767676,
                      ),
                    ),
                  ],
                ),
              ),
              if (compact)
                _StatusBadge(order.status)
              else
                DropdownButton<String>(
                  value: currentStatus,
                  underline: const SizedBox.shrink(),
                  items: options
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(_statusLabel(status)),
                        ),
                      )
                      .toList(),
                  onChanged: options.length == 1
                      ? null
                      : (status) {
                          if (status != null && status != order.status) {
                            context.read<BusinessBloc>().add(
                              BusinessOrderStatusChanged(order.id, status),
                            );
                          }
                        },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _statusLabel(String status) => switch (status) {
  'pending' => 'جديد',
  'confirmed' => 'تم التأكيد',
  'preparing' => 'قيد التجهيز',
  'outForDelivery' => 'في الطريق',
  'delivered' => 'تم التسليم',
  'cancelled' => 'ملغي',
  _ => status,
};

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: MerzoxColors.kColorDEEEF8,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(_statusLabel(status), style: const TextStyle(fontSize: 11)),
  );
}

class _Products extends StatelessWidget {
  final BusinessState state;
  const _Products({required this.state});

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _PageHeader(
        title: 'منتجاتي',
        subtitle: '${state.products.length} منتجاً وخدمة',
      ),
      Expanded(
        child: state.products.isEmpty
            ? _Empty(
                message: 'لم تضف منتجات بعد',
                action: FilledButton.icon(
                  onPressed: () => _showProductEditor(context),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة منتج'),
                ),
              )
            : ListView.builder(
                padding: const EdgeInsets.only(bottom: 20),
                itemCount: state.products.length,
                itemBuilder: (_, index) {
                  final product = state.products[index];
                  return Card(
                    color: Colors.white,
                    margin: const EdgeInsets.fromLTRB(16, 5, 16, 7),
                    child: ListTile(
                      leading: _ProductImage(product.imageUrl),
                      title: Text(
                        product.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        '${product.price.toStringAsFixed(0)} ₪ • ${product.isService ? 'خدمة' : 'منتج'}',
                      ),
                      trailing: PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'edit') {
                            _showProductEditor(context, product: product);
                          } else {
                            context.read<BusinessBloc>().add(
                              BusinessProductDeleted(product.id),
                            );
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('تعديل')),
                          PopupMenuItem(value: 'delete', child: Text('حذف')),
                        ],
                      ),
                      onTap: () =>
                          _showProductEditor(context, product: product),
                    ),
                  );
                },
              ),
      ),
    ],
  );
}

class _ProductImage extends StatelessWidget {
  final String url;
  const _ProductImage(this.url);
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(7),
    child: SizedBox(
      width: 52,
      height: 52,
      child: url.isEmpty
          ? Container(
              color: MerzoxColors.kColorDEEEF8,
              child: const Icon(Icons.inventory_2_outlined),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image_outlined),
            ),
    ),
  );
}

class _Profile extends StatelessWidget {
  final BusinessState state;
  final VoidCallback onLogout;
  const _Profile({required this.state, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    final business = state.business!;
    return ListView(
      children: [
        Container(
          height: 132,
          color: MerzoxColors.kColor3D5A80,
          alignment: Alignment.center,
          child: CircleAvatar(
            radius: 42,
            backgroundColor: Colors.white,
            backgroundImage: business.logoUrl.isEmpty
                ? null
                : NetworkImage(business.logoUrl),
            child: business.logoUrl.isNotEmpty
                ? null
                : Text(
                    business.name.isEmpty
                        ? 'M'
                        : business.name.characters.first,
                    style: TextStyle(
                      fontSize: 28,
                      color: MerzoxColors.kColor3D5A80,
                    ),
                  ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                business.name,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (business.englishName.isNotEmpty) Text(business.englishName),
              const SizedBox(height: 6),
              Text(
                business.category,
                style: TextStyle(color: MerzoxColors.kColor767676),
              ),
              const SizedBox(height: 18),
              _ProfileLine(Icons.location_on_outlined, business.address),
              _ProfileLine(Icons.description_outlined, business.description),
              if (business.attachmentUrl.isNotEmpty)
                _ProfileLine(Icons.attach_file_rounded, business.attachmentUrl),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _showProfileEditor(context, business),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('تعديل ملف الأعمال'),
                  style: FilledButton.styleFrom(
                    backgroundColor: MerzoxColors.kColor3D5A80,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _openStoreSettings(context, business),
                  icon: const Icon(Icons.settings_outlined),
                  label: Text('storeSettings.title'.tr()),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: MerzoxColors.kColor3D5A80),
                    foregroundColor: MerzoxColors.kColor3D5A80,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  // Routed rather than pushed locally, so the preview passes
                  // the business-only route guard and loads the storefront
                  // from the public contract instead of inheriting the
                  // merchant's own already-loaded owner state.
                  onPressed: () => context.push('/business/preview'),
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text('merchantPreview.open'.tr()),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: MerzoxColors.kColor3D5A80),
                    foregroundColor: MerzoxColors.kColor3D5A80,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('تسجيل الخروج'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

void _openStoreSettings(BuildContext context, OwnerBusiness business) {
  final bloc = context.read<BusinessBloc>();

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BlocProvider.value(
        value: bloc,
        child: StoreSettingsPage(business: business),
      ),
    ),
  );
}

class _ProfileLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _ProfileLine(this.icon, this.text);
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: MerzoxColors.kColor3D5A80),
    title: Text(text.isEmpty ? 'غير محدد' : text),
  );
}

class _BusinessNavigation extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  const _BusinessNavigation({
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: SizedBox(
      height: 82,
      child: Stack(
        alignment: Alignment.topCenter,
        clipBehavior: Clip.none,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x18000000),
                  blurRadius: 14,
                  offset: Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                _nav(Icons.home_outlined, Icons.home_rounded, 0),
                _nav(
                  Icons.receipt_long_outlined,
                  Icons.receipt_long_rounded,
                  1,
                ),
                const SizedBox(width: 72),
                _nav(Icons.inventory_2_outlined, Icons.inventory_2_rounded, 3),
                _nav(Icons.person_outline_rounded, Icons.person_rounded, 4),
              ],
            ),
          ),
          Positioned(
            top: -4,
            child: InkWell(
              onTap: () => onChanged(2),
              customBorder: const CircleBorder(),
              child: Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: MerzoxColors.kColorEE6C4D,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 5),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x30000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.add_rounded,
                  size: 30,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _nav(IconData icon, IconData selectedIcon, int index) => Expanded(
    child: InkWell(
      onTap: () => onChanged(index),
      child: Center(
        child: Icon(
          selectedIndex == index ? selectedIcon : icon,
          color: selectedIndex == index
              ? MerzoxColors.kColorEE6C4D
              : MerzoxColors.kColor8D99AE,
        ),
      ),
    ),
  );
}

class _Empty extends StatelessWidget {
  final String message;
  final Widget? action;
  const _Empty({required this.message, this.action});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(42),
    child: Column(
      children: [
        Icon(Icons.inbox_outlined, size: 54, color: MerzoxColors.kColor98C1D9),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        if (action != null) ...[const SizedBox(height: 16), action!],
      ],
    ),
  );
}

class _Failure extends StatelessWidget {
  final VoidCallback onRetry;
  const _Failure({required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('تعذر تحميل حساب الأعمال'),
        const SizedBox(height: 10),
        FilledButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    ),
  );
}

Future<void> _showProductEditor(
  BuildContext context, {
  OwnerProduct? product,
}) async {
  final bloc = context.read<BusinessBloc>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) =>
        BlocProvider.value(value: bloc, child: _ProductEditor(product)),
  );
}

class _ProductEditor extends StatefulWidget {
  final OwnerProduct? product;
  const _ProductEditor(this.product);
  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  final _key = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _costPrice;
  late final TextEditingController _stockQuantity;
  late final TextEditingController _discountPercent;
  late final TextEditingController _keywords;
  late final TextEditingController _images;

  late String _classification;
  late bool _isService;
  late bool _isActive;
  late bool _unlimitedStock;
  late bool _hasDiscount;

  /// The revision the shell was on when this sheet opened. The bloc bumps it
  /// only after the server confirms a write, so a change is the success signal.
  late final int _openedAtRevision;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final product = widget.product;

    // Edit mode initializes from real merchant data only. A missing value
    // becomes the schema default, never an invented example.
    _name = TextEditingController(text: product?.name ?? '');
    _description = TextEditingController(text: product?.description ?? '');
    _price = TextEditingController(
      text: product == null ? '' : _trimNumber(product.price),
    );
    _costPrice = TextEditingController(
      text: product?.costPrice == null ? '' : _trimNumber(product!.costPrice!),
    );
    _stockQuantity = TextEditingController(
      text: product == null || product.unlimitedStock
          ? ''
          : '${product.stockQuantity}',
    );
    _discountPercent = TextEditingController(
      text: product == null || product.discountPercent <= 0
          ? ''
          : _trimNumber(product.discountPercent),
    );
    _keywords = TextEditingController(
      text: product == null ? '' : product.keywords.join('، '),
    );
    _images = TextEditingController(
      text: product == null ? '' : product.imageUrls.join('\n'),
    );

    _classification = product?.classification ?? 'new';
    _isService = product?.isService ?? false;
    _isActive = product?.isActive ?? true;
    _unlimitedStock = product?.unlimitedStock ?? true;
    _hasDiscount = (product?.discountPercent ?? 0) > 0;
    _openedAtRevision = context.read<BusinessBloc>().state.revision;
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _description,
      _price,
      _costPrice,
      _stockQuantity,
      _discountPercent,
      _keywords,
      _images,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  List<String> _parsedKeywords() => _keywords.text
      .split(RegExp(r'[,،\n]'))
      .map((keyword) => keyword.trim())
      .where((keyword) => keyword.isNotEmpty)
      .toList();

  List<String> _parsedImages() => _images.text
      .split('\n')
      .map((url) => url.trim())
      .where((url) => url.isNotEmpty)
      .toList();

  /// Builds exactly the merchant-writable contract. Server-derived values
  /// (finalPrice, inStock, rating, identity) are never sent.
  Map<String, dynamic> _buildValues() {
    return {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'price': double.parse(_price.text.trim()),
      'costPrice': _costPrice.text.trim().isEmpty
          ? null
          : double.parse(_costPrice.text.trim()),
      'unlimitedStock': _unlimitedStock,
      // Omitted entirely when unlimited, so the payload can never describe a
      // finite quantity and unlimited stock at the same time.
      if (!_unlimitedStock)
        'stockQuantity': int.parse(_stockQuantity.text.trim()),
      'discountPercent': _hasDiscount && _discountPercent.text.trim().isNotEmpty
          ? double.parse(_discountPercent.text.trim())
          : 0,
      'keywords': _parsedKeywords(),
      'imageUrls': _parsedImages(),
      'classification': _classification,
      'isService': _isService,
      'isActive': _isActive,
    };
  }

  void _submit() {
    if (_submitted) return;
    if (_key.currentState?.validate() != true) return;

    setState(() => _submitted = true);
    context.read<BusinessBloc>().add(
      BusinessProductSaved(
        productId: widget.product?.id,
        values: _buildValues(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<BusinessBloc, BusinessState>(
      listenWhen: (previous, current) =>
          previous.revision != current.revision ||
          previous.status != current.status,
      listener: (context, state) {
        if (!_submitted) return;

        // Only a confirmed server write closes the sheet.
        if (state.revision != _openedAtRevision) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(content: Text('merchantProduct.saved'.tr())),
            );
          return;
        }

        // A failure keeps every entered value and re-enables the button.
        if (state.status == BusinessStatus.failure) {
          setState(() => _submitted = false);
        }
      },
      builder: (context, state) {
        final saving = _submitted && state.status == BusinessStatus.saving;

        return Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 22,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: _key,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.product == null
                          ? 'merchantProduct.addTitle'.tr()
                          : 'merchantProduct.editTitle'.tr(),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _editorField(
                      _name,
                      'merchantProduct.name'.tr(),
                      hint: 'merchantProduct.nameHint'.tr(),
                    ),
                    _editorField(
                      _description,
                      'merchantProduct.description'.tr(),
                      hint: 'merchantProduct.descriptionHint'.tr(),
                      maxLines: 3,
                      required: false,
                    ),
                    _editorField(
                      _price,
                      'merchantProduct.price'.tr(),
                      keyboardType: TextInputType.number,
                      validator: _positiveNumberValidator,
                    ),
                    _editorField(
                      _costPrice,
                      'merchantProduct.costPrice'.tr(),
                      hint: 'merchantProduct.costPriceHint'.tr(),
                      keyboardType: TextInputType.number,
                      required: false,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? null
                          : _positiveNumberValidator(value),
                    ),
                    SwitchListTile(
                      value: _unlimitedStock,
                      onChanged: (value) =>
                          setState(() => _unlimitedStock = value),
                      title: Text('merchantProduct.unlimited'.tr()),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (!_unlimitedStock)
                      _editorField(
                        _stockQuantity,
                        'merchantProduct.quantity'.tr(),
                        hint: 'merchantProduct.quantityHint'.tr(),
                        keyboardType: TextInputType.number,
                        validator: _stockValidator,
                      ),
                    SwitchListTile(
                      value: _hasDiscount,
                      onChanged: (value) =>
                          setState(() => _hasDiscount = value),
                      title: Text('merchantProduct.hasDiscount'.tr()),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (_hasDiscount) ...[
                      _editorField(
                        _discountPercent,
                        'merchantProduct.discountPercent'.tr(),
                        keyboardType: TextInputType.number,
                        validator: _discountValidator,
                      ),
                      _DerivedPricePreview(
                        price: _price.text,
                        discountPercent: _discountPercent.text,
                      ),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: _classification,
                      decoration: InputDecoration(
                        labelText: 'merchantProduct.classification'.tr(),
                        border: const OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'new', child: Text('جديد')),
                        DropdownMenuItem(
                          value: 'bestSelling',
                          child: Text('الأكثر مبيعاً'),
                        ),
                        DropdownMenuItem(value: 'offers', child: Text('عروض')),
                      ],
                      onChanged: (value) => _classification = value ?? 'new',
                    ),
                    const SizedBox(height: 12),
                    _editorField(
                      _keywords,
                      'merchantProduct.keywords'.tr(),
                      hint: 'merchantProduct.keywordsHint'.tr(),
                      required: false,
                      validator: (_) => _parsedKeywords().length > 20
                          ? 'merchantProduct.tooManyKeywords'.tr()
                          : null,
                    ),
                    _editorField(
                      _images,
                      'merchantProduct.images'.tr(),
                      hint: 'merchantProduct.imagesHint'.tr(),
                      maxLines: 3,
                      required: false,
                      validator: (_) => _parsedImages().length > 8
                          ? 'merchantProduct.tooManyImages'.tr()
                          : null,
                    ),
                    SwitchListTile(
                      value: _isService,
                      onChanged: (value) => setState(() => _isService = value),
                      title: Text('merchantProduct.isService'.tr()),
                      contentPadding: EdgeInsets.zero,
                    ),
                    SwitchListTile(
                      value: _isActive,
                      onChanged: (value) => setState(() => _isActive = value),
                      title: Text('merchantProduct.publish'.tr()),
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: saving ? null : _submit,
                      style: FilledButton.styleFrom(
                        backgroundColor: MerzoxColors.kColorEE6C4D,
                      ),
                      child: Text(
                        saving
                            ? 'merchantProduct.saving'.tr()
                            : 'merchantProduct.save'.tr(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String? _positiveNumberValidator(String? value) {
    final parsed = double.tryParse((value ?? '').trim());
    if (parsed == null || parsed < 0) {
      return 'merchantProduct.invalidNumber'.tr();
    }
    return null;
  }

  String? _stockValidator(String? value) {
    final parsed = int.tryParse((value ?? '').trim());
    if (parsed == null || parsed < 0) {
      return 'merchantProduct.invalidQuantity'.tr();
    }
    return null;
  }

  String? _discountValidator(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return null;

    final parsed = double.tryParse(raw);
    if (parsed == null || parsed < 0 || parsed > 100) {
      return 'merchantProduct.invalidDiscount'.tr();
    }
    return null;
  }

  Widget _editorField(
    TextEditingController controller,
    String label, {
    String? hint,
    int maxLines = 1,
    bool required = true,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
      validator:
          validator ??
          (value) => required && (value == null || value.trim().isEmpty)
              ? 'merchantProduct.required'.tr()
              : null,
    ),
  );
}

String _trimNumber(double value) =>
    value % 1 == 0 ? value.toStringAsFixed(0) : value.toString();

/// Shows what the customer will pay. Presentation only - the server recomputes
/// the authoritative final price from the stored base price and discount.
class _DerivedPricePreview extends StatelessWidget {
  final String price;
  final String discountPercent;

  const _DerivedPricePreview({
    required this.price,
    required this.discountPercent,
  });

  @override
  Widget build(BuildContext context) {
    final base = double.tryParse(price.trim());
    final percent = double.tryParse(discountPercent.trim());

    if (base == null || percent == null || percent <= 0 || percent > 100) {
      return const SizedBox.shrink();
    }

    final derived = base * (1 - percent / 100);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        '${'merchantProduct.priceAfterDiscount'.tr()}: '
        '${derived.toStringAsFixed(2)} ₪',
        style: const TextStyle(fontSize: 12, color: MerzoxColors.kColor767676),
      ),
    );
  }
}

Future<void> _showProfileEditor(
  BuildContext context,
  OwnerBusiness business,
) async {
  final bloc = context.read<BusinessBloc>();
  await showDialog<void>(
    context: context,
    builder: (_) =>
        BlocProvider.value(value: bloc, child: _ProfileEditor(business)),
  );
}

class _ProfileEditor extends StatefulWidget {
  final OwnerBusiness business;
  const _ProfileEditor(this.business);
  @override
  State<_ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<_ProfileEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.business.name,
  );
  late final TextEditingController _english = TextEditingController(
    text: widget.business.englishName,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.business.description,
  );
  late final TextEditingController _category = TextEditingController(
    text: widget.business.category,
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.business.address,
  );
  late final TextEditingController _attachment = TextEditingController(
    text: widget.business.attachmentUrl,
  );

  @override
  void dispose() {
    _name.dispose();
    _english.dispose();
    _description.dispose();
    _category.dispose();
    _address.dispose();
    _attachment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: AlertDialog(
      title: const Text('تعديل ملف الأعمال'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            children: [
              _field(_name, 'اسم المتجر'),
              _field(_english, 'الاسم بالإنجليزية'),
              _field(_description, 'النبذة', maxLines: 3),
              _field(_category, 'التصنيف'),
              _field(_address, 'العنوان'),
              _field(_attachment, 'رابط مرفق سجل المتجر'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
        FilledButton(
          onPressed: () {
            context.read<BusinessBloc>().add(
              BusinessProfileSaved({
                'name': _name.text.trim(),
                'englishName': _english.text.trim(),
                'description': _description.text.trim(),
                'category': _category.text.trim(),
                'address': _address.text.trim(),
                'attachmentUrl': _attachment.text.trim(),
              }),
            );
            Navigator.pop(context);
          },
          child: const Text('حفظ'),
        ),
      ],
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
}
