import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/colors.dart';
import '../../../services/api_service.dart';
import '../../authentication/bloc/auth_bloc.dart';
import '../models/business_models.dart';
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
          onPressed: () {},
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
                  itemBuilder: (_, index) =>
                      _OrderTile(order: state.orders[index]),
                ),
        ),
      ),
    ],
  );
}

class _OrderTile extends StatelessWidget {
  final OwnerOrder order;
  final bool compact;
  const _OrderTile({required this.order, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final currentStatus = _statuses.contains(order.status)
        ? order.status
        : 'pending';
    final options = <String>[currentStatus, ...?_nextStatuses[currentStatus]];

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 5, 16, 7),
      color: Colors.white,
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
                  Text(
                    order.customerName.isEmpty
                        ? 'عميل Merzox'
                        : order.customerName,
                    style: const TextStyle(fontWeight: FontWeight.w700),
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
    );
  }
}

const _statuses = [
  'pending',
  'confirmed',
  'preparing',
  'outForDelivery',
  'delivered',
  'cancelled',
];
const _nextStatuses = <String, List<String>>{
  'pending': ['confirmed', 'cancelled'],
  'confirmed': ['preparing', 'cancelled'],
  'preparing': ['outForDelivery', 'cancelled'],
  'outForDelivery': ['delivered'],
  'delivered': [],
  'cancelled': [],
};
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
            child: Text(
              business.name.isEmpty ? 'M' : business.name.characters.first,
              style: TextStyle(fontSize: 28, color: MerzoxColors.kColor3D5A80),
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
  BusinessProductApiModel? product,
}) async {
  final bloc = context.read<BusinessBloc>();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => BlocProvider.value(
      value: bloc,
      child: _ProductEditor(product: product),
    ),
  );
}

class _ProductEditor extends StatefulWidget {
  final BusinessProductApiModel? product;
  const _ProductEditor({this.product});
  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _image;
  late String _classification;
  late bool _isService;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _name = TextEditingController(text: product?.name ?? '');
    _description = TextEditingController(text: product?.description ?? '');
    _price = TextEditingController(
      text: product == null ? '' : product.price.toStringAsFixed(0),
    );
    _image = TextEditingController(text: product?.imageUrl ?? '');
    _classification = product?.classification ?? 'new';
    _isService = product?.isService ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _image.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Directionality(
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
                widget.product == null ? 'إضافة منتج جديد' : 'تعديل المنتج',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 18),
              _editorField(_name, 'اسم المنتج'),
              _editorField(_description, 'الوصف', maxLines: 3),
              _editorField(_price, 'السعر', keyboardType: TextInputType.number),
              _editorField(_image, 'رابط الصورة', required: false),
              DropdownButtonFormField<String>(
                initialValue: _classification,
                decoration: const InputDecoration(
                  labelText: 'التصنيف',
                  border: OutlineInputBorder(),
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
              SwitchListTile(
                value: _isService,
                onChanged: (value) => setState(() => _isService = value),
                title: const Text('هذا العنصر خدمة'),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () {
                  if (_key.currentState?.validate() != true) return;
                  context.read<BusinessBloc>().add(
                    BusinessProductSaved(
                      productId: widget.product?.id,
                      values: {
                        'name': _name.text.trim(),
                        'description': _description.text.trim(),
                        'price': double.parse(_price.text.trim()),
                        'imageUrl': _image.text.trim(),
                        'classification': _classification,
                        'isService': _isService,
                      },
                    ),
                  );
                  Navigator.pop(context);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: MerzoxColors.kColorEE6C4D,
                ),
                child: const Text('حفظ'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _editorField(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
    bool required = true,
    TextInputType? keyboardType,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 13),
    child: TextFormField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return 'هذا الحقل مطلوب';
        }
        if (controller == _price) {
          final price = double.tryParse(value ?? '');
          if (price == null || price < 0) return 'أدخل سعراً صحيحاً';
        }
        if (controller == _image && (value ?? '').trim().isNotEmpty) {
          final uri = Uri.tryParse(value!.trim());
          if (uri == null ||
              (uri.scheme != 'https' && uri.scheme != 'http') ||
              uri.host.isEmpty) {
            return 'أدخل رابط صورة صحيحاً';
          }
        }
        return null;
      },
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
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
