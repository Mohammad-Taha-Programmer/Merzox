import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/auth/auth_gate.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/features/cart/bloc/cart_bloc.dart';
import 'package:merzox/features/cart/bloc/cart_event.dart';
import 'package:merzox/features/cart/bloc/cart_state.dart';
import 'package:merzox/features/business_profile/pages/business_profile_page.dart';
import 'package:merzox/features/home/presentation/bloc/home_bloc.dart';
import 'package:merzox/features/home/presentation/bloc/home_event.dart';
import 'package:merzox/features/home/presentation/bloc/home_state_.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_bloc.dart';
import 'package:merzox/features/notification_preferences/bloc/notification_preference_event.dart';
import 'package:merzox/features/notification_preferences/widgets/notification_preference_control.dart';
import 'package:merzox/features/messages/bloc/messages_bloc.dart';
import 'package:merzox/features/messages/bloc/messages_event.dart';
import 'package:merzox/features/messages/pages/messages_inbox_view.dart';
import 'package:merzox/services/location_permission_service.dart';
import 'package:merzox/services/notification_preference_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../authentication/bloc/auth_bloc.dart';

class _StoredUserProfile {
  final String name;
  final String address;
  final String userType;
  final String email;
  final String phone;
  final String gender;

  const _StoredUserProfile({
    required this.name,
    required this.address,
    required this.userType,
    required this.email,
    required this.phone,
    required this.gender,
  });

  static Future<_StoredUserProfile> load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedName = prefs.getString(AuthBloc.nameKey)?.trim();
    final storedAddress = prefs.getString(AuthBloc.addressKey)?.trim();
    final storedUserType = prefs.getString(AuthBloc.userTypeKey)?.trim();
    final storedEmail = prefs.getString(AuthBloc.emailKey)?.trim();
    final storedPhone = prefs.getString(AuthBloc.phoneKey)?.trim();
    final storedGender = prefs.getString(AuthBloc.genderKey)?.trim();

    return _StoredUserProfile(
      name: storedName == null || storedName.isEmpty
          ? 'مستخدم Merzox'
          : storedName,
      address: storedAddress ?? '',
      userType: storedUserType == null || storedUserType.isEmpty
          ? 'normal'
          : storedUserType,
      email: storedEmail ?? '',
      phone: storedPhone ?? '',
      gender: storedGender ?? 'unspecified',
    );
  }
}

class HomeScreen extends StatelessWidget {
  final bool isGuest;
  final NotificationPreferenceGateway? notificationPreferenceGateway;
  final NotificationPreferenceSessionReader?
  notificationPreferenceSessionReader;

  const HomeScreen({
    super.key,
    required this.isGuest,
    this.notificationPreferenceGateway,
    this.notificationPreferenceSessionReader,
  });

  Future<void> _logout(BuildContext context) async {
    await AuthBloc.clearStoredSession();

    if (context.mounted) {
      context.go('/login');
    }
  }

  void _showAuthGate(BuildContext context) {
    AuthGate.run(context, onAuthenticated: () {});
  }

  void _openBusinessEnrollment(BuildContext context) {
    AuthGate.run(
      context,
      onAuthenticated: () {
        context.push('/business/enroll');
      },
    );
  }

  Future<void> _showLocationPrompt(BuildContext context, HomeBloc bloc) async {
    bloc.add(const HomeLocationPromptShown());
    final reason = bloc.state.locationPermissionReason;
    final service = LocationPermissionService();

    final granted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return Directionality(
          textDirection: Directionality.of(context),
          child: AlertDialog(
            title: const Text('السماح باستخدام موقعك؟'),
            content: Text(
              reason == 'nearby'
                  ? 'نحتاج موقعك لعرض المتاجر القريبة منك وترتيب النتائج حسب المسافة.'
                  : 'نطلب إذنك مرة واحدة حتى نتمكن من تخصيص المتاجر والخدمات القريبة عند الحاجة.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('لاحقاً'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: const Text('السماح'),
              ),
            ],
          ),
        );
      },
    );

    if (granted != true) {
      bloc.add(const HomeLocationPermissionAnswered(granted: false));
      return;
    }

    final status = await service.requestLocation();
    final isGranted = status == MerzoxLocationPermissionStatus.granted;

    if (context.mounted &&
        status == MerzoxLocationPermissionStatus.permanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'تم إيقاف إذن الموقع من إعدادات الجهاز. يمكنك تفعيله من إعدادات التطبيق.',
          ),
          action: SnackBarAction(
            label: 'الإعدادات',
            onPressed: service.openAppSettingsPage,
          ),
        ),
      );
    }

    bloc.add(HomeLocationPermissionAnswered(granted: isGranted));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<HomeBloc, HomeState>(
      listenWhen: (previous, current) {
        return current.shouldAskLocationPermission &&
            !previous.shouldAskLocationPermission;
      },
      listener: (context, state) {
        if (state.shouldAskLocationPermission) {
          _showLocationPrompt(context, context.read<HomeBloc>());
        }
      },
      builder: (context, state) {
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(
            child: switch (state.selectedTab) {
              0 => _HomeTab(
                state: state,
                isGuest: isGuest,
                onLogout: () => _logout(context),
                onProtectedAction: () => _showAuthGate(context),
                onBusinessEnrollment: () => _openBusinessEnrollment(context),
                onLocationRequested: () => context.read<HomeBloc>().add(
                  const HomeLocationServiceRequested(reason: 'nearby'),
                ),
              ),
              1 => _CartTab(
                isGuest: isGuest,
                onSignupPressed: () => context.go('/signup'),
                onLoginPressed: () => context.go('/login'),
                onExplorePressed: () {
                  context.read<HomeBloc>().add(const HomeTabChanged(0));
                },
              ),
              2 => _BusinessesTab(state: state),
              3 => _ChatTab(
                isGuest: isGuest,
                onSignupPressed: () => context.go('/signup'),
                onLoginPressed: () => context.go('/login'),
              ),
              4 => _ProfileTab(
                isGuest: isGuest,
                onLogout: () => _logout(context),
                onEditProfile: () => context.push('/profile/edit'),
                onOrders: () => context.push('/orders'),
                onMap: () => context.push('/map'),
                onFavorites: () => context.push('/favorites'),
                onAboutUs: () => context.push('/about-us'),
                onShareApp: () => context.push('/share-app'),
                onSignupPressed: () => context.go('/signup'),
                onLoginPressed: () => context.go('/login'),
                onProtectedAction: () => _openBusinessEnrollment(context),
                notificationPreferenceGateway: notificationPreferenceGateway,
                notificationPreferenceSessionReader:
                    notificationPreferenceSessionReader,
              ),
              _ => _ComingSoonTab(index: state.selectedTab),
            },
          ),
          bottomNavigationBar: _HomeBottomNavigationBar(
            selectedIndex: state.selectedTab,
            onChanged: (index) {
              Future<void>.delayed(Duration.zero, () {
                if (context.mounted) {
                  context.read<HomeBloc>().add(HomeTabChanged(index));
                }
              });
            },
          ),
        );
      },
    );
  }
}

class _HomeBottomNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const _HomeBottomNavigationBar({
    required this.selectedIndex,
    required this.onChanged,
  });

  static const _items = [
    _HomeNavData(
      label: 'الرئيسية',
      icon: Icons.home_outlined,
      selectedIcon: Icons.home_rounded,
    ),
    _HomeNavData(
      label: 'المتاجر',
      icon: Icons.storefront_outlined,
      selectedIcon: Icons.storefront_rounded,
    ),
    _HomeNavData(
      label: 'السلة',
      icon: Icons.shopping_bag_outlined,
      selectedIcon: Icons.shopping_bag_rounded,
    ),
    _HomeNavData(
      label: 'الرسائل',
      icon: Icons.chat_bubble_outline_rounded,
      selectedIcon: Icons.chat_bubble_rounded,
    ),
    _HomeNavData(
      label: 'الحساب',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 92,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Positioned.fill(
              top: 22,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 22,
                      offset: const Offset(0, -7),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              child: Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 18,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              top: 22,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Row(
                  children: [
                    Expanded(
                      child: _HomeNavItem(
                        data: _items[0],
                        selected: selectedIndex == 0,
                        onTap: () => onChanged(0),
                      ),
                    ),
                    Expanded(
                      child: _HomeNavItem(
                        data: _items[2],
                        selected: selectedIndex == 1,
                        onTap: () => onChanged(1),
                      ),
                    ),
                    const SizedBox(width: 92),
                    Expanded(
                      child: _HomeNavItem(
                        data: _items[3],
                        selected: selectedIndex == 3,
                        onTap: () => onChanged(3),
                      ),
                    ),
                    Expanded(
                      child: _HomeNavItem(
                        data: _items[4],
                        selected: selectedIndex == 4,
                        onTap: () => onChanged(4),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 7,
              child: _CenterStoreButton(
                data: _items[1],
                selected: selectedIndex == 2,
                onTap: () => onChanged(2),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeNavData {
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  const _HomeNavData({
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });
}

class _HomeNavItem extends StatelessWidget {
  final _HomeNavData data;
  final bool selected;
  final VoidCallback onTap;

  const _HomeNavItem({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final inactiveColor = MerzoxColors.kColor8D99AE;

    return Semantics(
      label: data.label,
      button: true,
      selected: selected,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: selected ? MerzoxColors.kColorFDF1EC : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Icon(
              selected ? data.selectedIcon : data.icon,
              color: selected ? MerzoxColors.kColorEE6C4D : inactiveColor,
              size: selected ? 26 : 25,
            ),
          ),
        ),
      ),
    );
  }
}

class _CenterStoreButton extends StatelessWidget {
  final _HomeNavData data;
  final bool selected;
  final VoidCallback onTap;

  const _CenterStoreButton({
    required this.data,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: data.label,
      button: true,
      selected: selected,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: selected ? 62 : 58,
          height: selected ? 62 : 58,
          decoration: BoxDecoration(
            color: MerzoxColors.kColorEE6C4D,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: MerzoxColors.kColorEE6C4D.withValues(alpha: 0.32),
                blurRadius: selected ? 18 : 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            selected ? data.selectedIcon : data.icon,
            color: Colors.white,
            size: selected ? 31 : 29,
          ),
        ),
      ),
    );
  }
}

class _HomeTab extends StatelessWidget {
  final HomeState state;
  final bool isGuest;
  final VoidCallback onLogout;
  final VoidCallback onProtectedAction;
  final VoidCallback onLocationRequested;
  final VoidCallback onBusinessEnrollment;

  const _HomeTab({
    required this.state,
    required this.isGuest,
    required this.onLogout,
    required this.onProtectedAction,
    required this.onLocationRequested,
    required this.onBusinessEnrollment,
  });

  @override
  Widget build(BuildContext context) {
    final newBusinesses = _filtered(state.newBusinesses, state.searchQuery);
    final bestBusinesses = _filtered(state.bestBusinesses, state.searchQuery);
    final discountedBusinesses = _filtered(
      state.discountedBusinesses,
      state.searchQuery,
    );
    final nearbyBusinesses = _filtered(
      state.nearbyBusinesses,
      state.searchQuery,
    );

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HomeTopBar(
                  isGuest: isGuest,
                  onLogout: onLogout,
                  onProtectedAction: onProtectedAction,
                ),
                const SizedBox(height: 24),
                _AdvertisementCard(onPressed: onBusinessEnrollment),
                const SizedBox(height: 16),
                _SearchBox(onTap: () => context.push('/search')),
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
        _BusinessSection(
          title: 'متاجر جديدة',
          businesses: newBusinesses,
          status: state.newBusinessesStatus,
          errorMessage: state.newBusinessesError,
          onRetry: () => context.read<HomeBloc>().add(
            const HomeCatalogSectionRetryRequested(HomeCatalogSection.newest),
          ),
          followedBusinessIds: state.followedBusinessIds,
        ),
        _BusinessSection(
          title: 'أفضل المتاجر',
          businesses: bestBusinesses,
          status: state.bestBusinessesStatus,
          errorMessage: state.bestBusinessesError,
          onRetry: () => context.read<HomeBloc>().add(
            const HomeCatalogSectionRetryRequested(HomeCatalogSection.best),
          ),
          followedBusinessIds: state.followedBusinessIds,
        ),
        _BusinessSection(
          title: 'المتاجر التي يوجد فيها عروض',
          businesses: discountedBusinesses,
          status: state.discountedBusinessesStatus,
          errorMessage: state.discountedBusinessesError,
          onRetry: () => context.read<HomeBloc>().add(
            const HomeCatalogSectionRetryRequested(HomeCatalogSection.offers),
          ),
          followedBusinessIds: state.followedBusinessIds,
        ),
        SliverToBoxAdapter(
          child: _LocationStatusCard(
            granted: state.locationPermissionGranted,
            handled: state.locationPermissionHandled,
            onRequest: onLocationRequested,
          ),
        ),
        _BusinessSection(
          title: 'المتاجر القريبة منك',
          businesses: nearbyBusinesses,
          status: state.nearbyBusinessesStatus,
          errorMessage: state.nearbyBusinessesError,
          onRetry: () => context.read<HomeBloc>().add(
            const HomeCatalogSectionRetryRequested(HomeCatalogSection.nearby),
          ),
          followedBusinessIds: state.followedBusinessIds,
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  List<HomeBusiness> _filtered(List<HomeBusiness> source, String query) {
    return source.where((business) => business.matches(query)).toList();
  }
}

class _HomeTopBar extends StatelessWidget {
  final bool isGuest;
  final VoidCallback onLogout;
  final VoidCallback onProtectedAction;

  const _HomeTopBar({
    required this.isGuest,
    required this.onLogout,
    required this.onProtectedAction,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: MerzoxColors.kColorDEEEF8,
                  child: Icon(
                    isGuest
                        ? Icons.person_outline_rounded
                        : Icons.person_rounded,
                    color: MerzoxColors.kColor3D5A80,
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (isGuest)
                      const Text(
                        'أهلاً، ضيف',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF2B2B2B),
                        ),
                      )
                    else
                      FutureBuilder<_StoredUserProfile>(
                        future: _StoredUserProfile.load(),
                        builder: (context, snapshot) {
                          final name = snapshot.data?.name ?? 'مستخدم Merzox';

                          return Text(
                            'أهلاً، $name',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF2B2B2B),
                            ),
                          );
                        },
                      ),
                    Text(
                      isGuest ? 'تصفح فقط' : 'مرحباً بك في Merzox',
                      style: TextStyle(
                        fontSize: 12,
                        color: MerzoxColors.kColor8D99AE,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: IconButton(
              tooltip: 'الإشعارات',
              onPressed: isGuest ? onProtectedAction : () {},
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_none_rounded, size: 28),
                  PositionedDirectional(
                    top: 1,
                    end: 1,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: MerzoxColors.kColorEE6C4D,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (!isGuest)
            Align(
              alignment: AlignmentDirectional.center,
              child: SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  tooltip: 'تسجيل الخروج',
                  onPressed: onLogout,
                  icon: Icon(
                    Icons.logout_rounded,
                    color: MerzoxColors.kColor8D99AE,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AdvertisementCard extends StatelessWidget {
  final VoidCallback onPressed;

  const _AdvertisementCard({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 142,
      decoration: BoxDecoration(
        color: MerzoxColors.kColor3D5A80,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'ادخل وكن من أفضل التجار',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Text(
                  'اشترك في عضوية التجار واعرض منتجاتك لجيرانك.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.82),
                    fontSize: 12,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 32,
                  child: FilledButton(
                    onPressed: onPressed,
                    style: FilledButton.styleFrom(
                      backgroundColor: MerzoxColors.kColorEE6C4D,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: const Text('إنشاء حساب'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 38,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBox extends StatelessWidget {
  final VoidCallback onTap;

  const _SearchBox({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: TextField(
        readOnly: true,
        onTap: onTap,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'ابحث عن أي متجر أو منتج تريده',
          hintStyle: TextStyle(color: MerzoxColors.kColor9F9F9F, fontSize: 14),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: MerzoxColors.kColor98C1D9,
          ),
          filled: true,
          fillColor: MerzoxColors.kColorF9F9F9,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
      ),
    );
  }
}

class _BusinessSection extends StatelessWidget {
  final String title;
  final List<HomeBusiness> businesses;
  final HomeSectionStatus status;
  final String errorMessage;
  final VoidCallback onRetry;
  final Set<String> followedBusinessIds;

  const _BusinessSection({
    required this.title,
    required this.businesses,
    required this.status,
    required this.errorMessage,
    required this.onRetry,
    required this.followedBusinessIds,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.only(bottom: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                title,
                textAlign: TextAlign.start,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2B2B2B),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (status == HomeSectionStatus.loading)
              const SizedBox(
                height: 96,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (status == HomeSectionStatus.failure)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _CatalogFailureState(
                  errorMessage: errorMessage,
                  onRetry: onRetry,
                ),
              )
            else if (businesses.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _EmptySearchResult(title: title),
              )
            else
              SizedBox(
                height: 224,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemBuilder: (context, index) {
                    final business = businesses[index];

                    return _BusinessCard(
                      business: business,
                      followed: followedBusinessIds.contains(business.id),
                      onFollowPressed: () => AuthGate.run(
                        context,
                        onAuthenticated: () => context.read<HomeBloc>().add(
                          HomeBusinessFollowToggled(business.id),
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemCount: businesses.length,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  final HomeBusiness business;
  final bool followed;
  final VoidCallback onFollowPressed;
  final double? width;

  const _BusinessCard({
    required this.business,
    required this.followed,
    required this.onFollowPressed,
    this.width = 164,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: MerzoxColors.kColorEFEFEF),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _openBusinessProfile(context, business),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Stack(
                      children: [
                        Container(
                          height: 72,
                          decoration: BoxDecoration(
                            color: Color(business.colorValue),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.storefront_rounded,
                              size: 34,
                              color: MerzoxColors.kColor3D5A80,
                            ),
                          ),
                        ),
                        if (business.discount != null)
                          PositionedDirectional(
                            top: 6,
                            start: 6,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: MerzoxColors.kColorEE6C4D,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                business.discount!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Text(
                      business.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      business.category,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: MerzoxColors.kColor767676,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _BusinessIdBadge(id: business.displayId),
                    const SizedBox(height: 8),
                    _RatingStars(rating: business.rating),
                    const Spacer(),
                    if (business.distanceMeters case final distance?)
                      Padding(
                        padding: const EdgeInsetsDirectional.only(end: 38),
                        child: Text(
                          _businessDistanceText(distance),
                          style: TextStyle(
                            fontSize: 12,
                            color: MerzoxColors.kColor8D99AE,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              PositionedDirectional(
                bottom: 8,
                start: 8,
                child: _FollowButton(
                  followed: followed,
                  onPressed: onFollowPressed,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusinessIdBadge extends StatelessWidget {
  final String id;

  const _BusinessIdBadge({required this.id});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: MerzoxColors.kColorF5F9FC,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: MerzoxColors.kColorDEEEF8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.ltr,
          children: [
            Text(
              'ID:',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: MerzoxColors.kColor3D5A80,
              ),
            ),
            const SizedBox(width: 3),
            Text(
              id,
              style: const TextStyle(fontSize: 11, color: Color(0xFF2B2B2B)),
            ),
          ],
        ),
      ),
    );
  }
}

class _RatingStars extends StatelessWidget {
  final double rating;

  const _RatingStars({required this.rating});

  @override
  Widget build(BuildContext context) {
    final roundedRating = rating.round().clamp(0, 5);

    return Row(
      children: [
        ...List.generate(5, (index) {
          return Icon(
            index < roundedRating
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
            size: 15,
            color: MerzoxColors.kColorFBB300,
          );
        }),
        const SizedBox(width: 4),
        Text(
          rating.toStringAsFixed(1),
          style: const TextStyle(fontSize: 11, color: Color(0xFF2B2B2B)),
        ),
      ],
    );
  }
}

class _FollowButton extends StatelessWidget {
  final bool followed;
  final VoidCallback onPressed;

  const _FollowButton({required this.followed, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: followed ? 'إلغاء المتابعة' : 'متابعة النشاطات',
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: followed
                ? MerzoxColors.kColorFEE3DC
                : MerzoxColors.kColorF5F9FC,
            shape: BoxShape.circle,
            border: Border.all(
              color: followed
                  ? MerzoxColors.kColorEE6C4D
                  : MerzoxColors.kColorDEEEF8,
            ),
          ),
          child: Text(
            followed ? '🥰' : '😔',
            style: const TextStyle(fontSize: 18),
          ),
        ),
      ),
    );
  }
}

class _LocationStatusCard extends StatelessWidget {
  final bool granted;
  final bool handled;
  final VoidCallback onRequest;

  const _LocationStatusCard({
    required this.granted,
    required this.handled,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    if (granted || !handled) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      child: Material(
        color: MerzoxColors.kColorFDF1EC,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onRequest,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(
                  Icons.location_off_rounded,
                  color: MerzoxColors.kColorEE6C4D,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'فعّل الموقع للحصول على نتائج أدق للمتاجر القريبة منك.',
                    style: TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
                Icon(
                  Icons.chevron_left_rounded,
                  color: MerzoxColors.kColor3D5A80,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptySearchResult extends StatelessWidget {
  final String title;

  const _EmptySearchResult({required this.title});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF9F9F9,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'لا توجد نتائج في $title',
        style: TextStyle(color: MerzoxColors.kColor767676),
      ),
    );
  }
}

class _CatalogFailureState extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  const _CatalogFailureState({
    required this.errorMessage,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final message = errorMessage.contains('.')
        ? errorMessage.tr()
        : errorMessage;

    return Container(
      constraints: const BoxConstraints(minHeight: 96),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF9F9F9,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: MerzoxColors.kColor98C1D9),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message.isEmpty ? 'catalog.loadError'.tr() : message,
              style: TextStyle(fontSize: 12, color: MerzoxColors.kColor767676),
            ),
          ),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text('common.retry'.tr()),
          ),
        ],
      ),
    );
  }
}

String _businessDistanceText(int meters) {
  if (meters < 1000) {
    return 'map.distanceMeters'.tr(args: ['$meters']);
  }

  final kilometers = meters / 1000;
  final value = kilometers >= 10
      ? kilometers.toStringAsFixed(0)
      : kilometers.toStringAsFixed(1);
  return 'map.distanceKilometers'.tr(args: [value]);
}

class _PlainTabTitle extends StatelessWidget {
  final String title;

  const _PlainTabTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Center(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF2B2B2B),
          ),
        ),
      ),
    );
  }
}

class _GuestLoginTabState extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback onSignupPressed;
  final VoidCallback onLoginPressed;

  const _GuestLoginTabState({
    required this.title,
    required this.message,
    required this.onSignupPressed,
    required this.onLoginPressed,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(34, 18, 34, 118),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 136),
            child: Column(
              children: [
                _PlainTabTitle(title: title),
                SizedBox(height: constraints.maxHeight < 680 ? 62 : 108),
                const _GuestAvatarMark(),
                const SizedBox(height: 34),
                const Text(
                  'يرجى تسجيل الدخول',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF2B2B2B),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.65,
                    color: MerzoxColors.kColor767676,
                  ),
                ),
                const SizedBox(height: 58),
                FilledButton(
                  onPressed: onSignupPressed,
                  style: FilledButton.styleFrom(
                    backgroundColor: MerzoxColors.kColorEE6C4D,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text(
                    'حساب إنشاء',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: onLoginPressed,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2B2B2B),
                    side: BorderSide(color: MerzoxColors.kColorEE6C4D),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text(
                    'تسجيل دخول',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GuestAvatarMark extends StatelessWidget {
  const _GuestAvatarMark();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 166,
      height: 166,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              color: MerzoxColors.kColor95BDD5,
              shape: BoxShape.circle,
            ),
          ),
          Positioned(
            top: 46,
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            bottom: 22,
            child: Container(
              width: 104,
              height: 58,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(58)),
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: MerzoxColors.kColor3D5A80,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: const Icon(Icons.add_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartTab extends StatelessWidget {
  final bool isGuest;
  final VoidCallback onSignupPressed;
  final VoidCallback onLoginPressed;
  final VoidCallback onExplorePressed;

  const _CartTab({
    required this.isGuest,
    required this.onSignupPressed,
    required this.onLoginPressed,
    required this.onExplorePressed,
  });

  @override
  Widget build(BuildContext context) {
    if (isGuest) {
      return _GuestLoginTabState(
        title: 'السلة',
        message: 'لعرض محتويات السلة الخاصة بك، يرجى تسجيل الدخول أولا',
        onSignupPressed: onSignupPressed,
        onLoginPressed: onLoginPressed,
      );
    }

    return BlocProvider(
      create: (_) => CartBloc()..add(const CartStarted()),
      child: _CartItemsView(onExplorePressed: onExplorePressed),
    );
  }
}

class _CartItemsView extends StatelessWidget {
  final VoidCallback onExplorePressed;

  const _CartItemsView({required this.onExplorePressed});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CartBloc, CartState>(
      listenWhen: (previous, current) =>
          previous.messageCode != current.messageCode ||
          previous.errorMessage != current.errorMessage,
      listener: (context, state) {
        final code = state.messageCode.isNotEmpty
            ? state.messageCode
            : state.errorMessage;
        if (code.isEmpty) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(code.tr()),
            action: state.messageCode.isEmpty
                ? null
                : SnackBarAction(
                    label: 'orders.title'.tr(),
                    onPressed: () => context.push('/orders'),
                  ),
          ),
        );
      },
      builder: (context, state) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 118),
          children: [
            const _PlainTabTitle(title: 'السلة'),
            if (state.status == CartStatus.loading)
              const Padding(
                padding: EdgeInsets.only(top: 160),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.items.isEmpty)
              _EmptyCartState(onExplorePressed: onExplorePressed)
            else ...[
              const SizedBox(height: 20),
              ...state.items.map(
                (item) => _CartItemTile(
                  item: item,
                  onRemove: () {
                    context.read<CartBloc>().add(CartItemRemoved(item.raw));
                  },
                ),
              ),
              const SizedBox(height: 18),
              _CartSummaryCard(
                subtotal: state.subtotal,
                onCheckoutPressed: state.status == CartStatus.checkingOut
                    ? null
                    : () => AuthGate.run(
                        context,
                        onAuthenticated: () => context.read<CartBloc>().add(
                          const CartCheckoutRequested(),
                        ),
                      ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _EmptyCartState extends StatelessWidget {
  final VoidCallback onExplorePressed;

  const _EmptyCartState({required this.onExplorePressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height - 210,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CustomPaint(
            size: const Size(122, 156),
            painter: _EmptyCartBagPainter(),
          ),
          const SizedBox(height: 28),
          const Text(
            'عذراً، السلة فارغة',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2B2B2B),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'لا يوجد منتجات في السلة، استكمل التسوق\nواضف أي شيء تريده',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.65,
              color: MerzoxColors.kColor707070,
            ),
          ),
          const SizedBox(height: 58),
          SizedBox(
            width: 204,
            height: 48,
            child: FilledButton(
              onPressed: onExplorePressed,
              style: FilledButton.styleFrom(
                backgroundColor: MerzoxColors.kColorEE6C4D,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              child: const Text(
                'استكشف التسوق',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCartBagPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MerzoxColors.kColor3D5A80
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final body = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.08,
        size.height * 0.25,
        size.width * 0.84,
        size.height * 0.65,
      ),
      const Radius.circular(5),
    );
    canvas.drawRRect(body, paint);
    canvas.drawLine(
      Offset(size.width * 0.08, size.height * 0.32),
      Offset(size.width * 0.92, size.height * 0.32),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * 0.08, size.height * 0.82),
      Offset(size.width * 0.92, size.height * 0.82),
      paint,
    );

    final handle = Path()
      ..moveTo(size.width * 0.38, size.height * 0.25)
      ..lineTo(size.width * 0.38, size.height * 0.16)
      ..quadraticBezierTo(
        size.width * 0.38,
        size.height * 0.08,
        size.width * 0.5,
        size.height * 0.08,
      )
      ..quadraticBezierTo(
        size.width * 0.62,
        size.height * 0.08,
        size.width * 0.62,
        size.height * 0.16,
      )
      ..lineTo(size.width * 0.62, size.height * 0.25);
    canvas.drawPath(handle, paint);

    final fillPaint = Paint()
      ..color = MerzoxColors.kColor3D5A80
      ..style = PaintingStyle.fill;
    canvas.drawCircle(
      Offset(size.width * 0.43, size.height * 0.56),
      3.5,
      fillPaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.57, size.height * 0.56),
      3.5,
      fillPaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.42, size.height * 0.67),
      Offset(size.width * 0.58, size.height * 0.67),
      paint..strokeWidth = 2.2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CartItemTile extends StatelessWidget {
  final CartItem item;
  final VoidCallback onRemove;

  const _CartItemTile({required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MerzoxColors.kColorEFEFEF),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.025),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 72,
              height: 72,
              child: item.imageUrl.isEmpty
                  ? const _CartImageFallback()
                  : Image.network(
                      item.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const _CartImageFallback(),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'الكمية: ${item.quantity}',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontSize: 12,
                    color: MerzoxColors.kColor767676,
                  ),
                ),
                // Shown only when the public contract said so on the last
                // refresh; checkout refuses while any line reads like this.
                if (!item.inStock)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'catalog.outOfStock'.tr(),
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: MerzoxColors.kColorEE6C4D,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Text(
                      '\u20AA ${item.total.toStringAsFixed(0)}',
                      textDirection: TextDirection.ltr,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: MerzoxColors.kColor3D5A80,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'إزالة',
                      onPressed: onRemove,
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: MerzoxColors.kColorEE6C4D,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CartImageFallback extends StatelessWidget {
  const _CartImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: MerzoxColors.kColorEEF6FB,
      child: Icon(
        Icons.shopping_bag_outlined,
        color: MerzoxColors.kColor3D5A80,
      ),
    );
  }
}

class _BusinessesTab extends StatefulWidget {
  final HomeState state;

  const _BusinessesTab({required this.state});

  @override
  State<_BusinessesTab> createState() => _BusinessesTabState();
}

class _BusinessesTabState extends State<_BusinessesTab> {
  late final ScrollController _scrollController;
  bool _paginationRequestScheduled = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _paginationRequestScheduled ||
        widget.state.isLoadingAllBusinesses ||
        !widget.state.hasMoreAllBusinesses) {
      return;
    }

    final position = _scrollController.position;
    if (position.extentAfter < 520) {
      _paginationRequestScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _paginationRequestScheduled = false;

        if (!mounted) {
          return;
        }

        context.read<HomeBloc>().add(
          const HomeAllBusinessesNextPageRequested(),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final businesses = widget.state.allBusinesses
        .where((business) => business.matches(widget.state.searchQuery))
        .toList();
    final rows = <Widget>[
      for (var index = 0; index < businesses.length; index += 2) ...[
        _AllBusinessesRow(
          first: businesses[index],
          second: index + 1 < businesses.length ? businesses[index + 1] : null,
          followedBusinessIds: widget.state.followedBusinessIds,
        ),
        if (index % 4 == 2) ...[
          const SizedBox(height: 14),
          const _AllBusinessesAdvertisementSlider(),
        ],
        const SizedBox(height: 14),
      ],
    ];

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 118),
      children: [
        const _AllBusinessesTopBar(),
        const SizedBox(height: 18),
        _SearchBox(onTap: () => context.push('/search')),
        const SizedBox(height: 18),
        if (widget.state.allBusinessesStatus == HomeSectionStatus.loading &&
            businesses.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 120),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (widget.state.allBusinessesStatus ==
                HomeSectionStatus.failure &&
            businesses.isEmpty)
          _CatalogFailureState(
            errorMessage: widget.state.allBusinessesError,
            onRetry: () => context.read<HomeBloc>().add(
              const HomeCatalogSectionRetryRequested(HomeCatalogSection.all),
            ),
          )
        else if (businesses.isEmpty)
          const _EmptyFeatureState(
            icon: Icons.search_off_rounded,
            title: 'لا توجد نتائج',
            message: 'جرّب البحث باسم متجر أو منتج آخر.',
          )
        else ...[
          ...rows,
          if (widget.state.isLoadingAllBusinesses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: CircularProgressIndicator(
                  color: MerzoxColors.kColorEE6C4D,
                ),
              ),
            )
          else if (widget.state.allBusinessesStatus ==
              HomeSectionStatus.failure)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: _CatalogFailureState(
                errorMessage: widget.state.allBusinessesError,
                onRetry: () => context.read<HomeBloc>().add(
                  const HomeCatalogSectionRetryRequested(
                    HomeCatalogSection.all,
                  ),
                ),
              ),
            )
          else if (widget.state.hasMoreAllBusinesses)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Center(
                child: Text(
                  'مرر لعرض المزيد من المتاجر',
                  style: TextStyle(
                    fontSize: 12,
                    color: MerzoxColors.kColor8D99AE,
                  ),
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _AllBusinessesTopBar extends StatelessWidget {
  const _AllBusinessesTopBar();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Center(
            child: Text(
              'المتاجر',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2B2B2B),
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  color: MerzoxColors.kColor3D5A80,
                  size: 20,
                ),
                PositionedDirectional(
                  top: 1,
                  end: -1,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: MerzoxColors.kColorEE6C4D,
                      shape: BoxShape.circle,
                    ),
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

class _AllBusinessesRow extends StatelessWidget {
  final HomeBusiness first;
  final HomeBusiness? second;
  final Set<String> followedBusinessIds;

  const _AllBusinessesRow({
    required this.first,
    required this.second,
    required this.followedBusinessIds,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SizedBox(
            height: 224,
            child: _BusinessCard(
              business: first,
              followed: followedBusinessIds.contains(first.id),
              onFollowPressed: () => _toggleFollow(context, first.id),
              width: null,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: second == null
              ? const SizedBox(height: 224)
              : SizedBox(
                  height: 224,
                  child: _BusinessCard(
                    business: second!,
                    followed: followedBusinessIds.contains(second!.id),
                    onFollowPressed: () => _toggleFollow(context, second!.id),
                    width: null,
                  ),
                ),
        ),
      ],
    );
  }

  void _toggleFollow(BuildContext context, String businessId) {
    AuthGate.run(
      context,
      onAuthenticated: () =>
          context.read<HomeBloc>().add(HomeBusinessFollowToggled(businessId)),
    );
  }
}

class _AllBusinessesAdvertisementSlider extends StatefulWidget {
  const _AllBusinessesAdvertisementSlider();

  @override
  State<_AllBusinessesAdvertisementSlider> createState() =>
      _AllBusinessesAdvertisementSliderState();
}

class _AllBusinessesAdvertisementSliderState
    extends State<_AllBusinessesAdvertisementSlider> {
  late final PageController _pageController;
  int _currentIndex = 0;

  static const _ads = [
    _AllBusinessesAdData(
      brand: 'Bicto',
      caption: 'يقوم فريق تطبيق Bicto بمساعدتك إعلانية',
      colorValue: 0xFF3D5A80,
    ),
    _AllBusinessesAdData(
      brand: 'Merzox',
      caption: 'اكتشف عروضا جديدة من المتاجر القريبة منك',
      colorValue: 0xFF293241,
    ),
    _AllBusinessesAdData(
      brand: 'Mx',
      caption: 'مساحة إعلانية للمتاجر والخدمات المحلية',
      colorValue: 0xFF446B8F,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.88);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 94,
      child: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemBuilder: (context, index) {
                return _MiniAdvertisementPanel(data: _ads[index]);
              },
              itemCount: _ads.length,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_ads.length, (index) {
              final selected = index == _currentIndex;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: selected ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: selected
                      ? MerzoxColors.kColorEE6C4D
                      : MerzoxColors.kColorD8D8D8,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _AllBusinessesAdData {
  final String brand;
  final String caption;
  final int colorValue;

  const _AllBusinessesAdData({
    required this.brand,
    required this.caption,
    required this.colorValue,
  });
}

class _MiniAdvertisementPanel extends StatelessWidget {
  final _AllBusinessesAdData data;

  const _MiniAdvertisementPanel({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: Color(data.colorValue),
        borderRadius: BorderRadius.circular(4),
      ),
      child: CustomPaint(
        painter: _AdPatternPainter(),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                data.brand,
                style: TextStyle(
                  fontFamily: 'Minion',
                  fontSize: 24,
                  color: MerzoxColors.kColorEE6C4D,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  data.caption,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    for (var x = -20.0; x < size.width; x += 24) {
      for (var y = -20.0; y < size.height; y += 24) {
        canvas.drawCircle(Offset(x, y), 10, paint);
        canvas.drawLine(Offset(x - 6, y), Offset(x + 6, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ChatTab extends StatelessWidget {
  final bool isGuest;
  final VoidCallback onSignupPressed;
  final VoidCallback onLoginPressed;

  const _ChatTab({
    required this.isGuest,
    required this.onSignupPressed,
    required this.onLoginPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (isGuest) {
      return _GuestLoginTabState(
        title: 'messages.title'.tr(),
        message: 'messages.guestHint'.tr(),
        onSignupPressed: onSignupPressed,
        onLoginPressed: onLoginPressed,
      );
    }

    return BlocProvider(
      create: (_) => MessagesBloc()..add(const MessagesStarted()),
      child: MessagesInboxView(title: 'messages.title'.tr()),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  final bool isGuest;
  final VoidCallback onLogout;
  final VoidCallback onEditProfile;
  final VoidCallback onOrders;
  final VoidCallback onMap;
  final VoidCallback onFavorites;
  final VoidCallback onAboutUs;
  final VoidCallback onShareApp;
  final VoidCallback onSignupPressed;
  final VoidCallback onLoginPressed;
  final VoidCallback onProtectedAction;
  final NotificationPreferenceGateway? notificationPreferenceGateway;
  final NotificationPreferenceSessionReader?
  notificationPreferenceSessionReader;

  const _ProfileTab({
    required this.isGuest,
    required this.onLogout,
    required this.onEditProfile,
    required this.onOrders,
    required this.onMap,
    required this.onFavorites,
    required this.onAboutUs,
    required this.onShareApp,
    required this.onSignupPressed,
    required this.onLoginPressed,
    required this.onProtectedAction,
    this.notificationPreferenceGateway,
    this.notificationPreferenceSessionReader,
  });

  @override
  Widget build(BuildContext context) {
    if (isGuest) {
      return _GuestLoginTabState(
        title: 'الملف الشخصي',
        message: 'لعرض حسابك وتعديل بياناتك، يرجى تسجيل الدخول أولا',
        onSignupPressed: onSignupPressed,
        onLoginPressed: onLoginPressed,
      );
    }

    return BlocProvider(
      create: (_) => NotificationPreferenceBloc(
        gateway: notificationPreferenceGateway,
        sessionReader: notificationPreferenceSessionReader,
      )..add(const NotificationPreferenceStarted()),
      child: _ProfileXdContent(
        onProtectedAction: onProtectedAction,
        onEditProfile: onEditProfile,
        onOrders: onOrders,
        onMap: onMap,
        onFavorites: onFavorites,
        onAboutUs: onAboutUs,
        onShareApp: onShareApp,
        onLogout: onLogout,
      ),
    );
  }
}

class _ProfileXdContent extends StatefulWidget {
  final VoidCallback onProtectedAction;
  final VoidCallback onEditProfile;
  final VoidCallback onOrders;
  final VoidCallback onMap;
  final VoidCallback onFavorites;
  final VoidCallback onAboutUs;
  final VoidCallback onShareApp;
  final VoidCallback onLogout;

  const _ProfileXdContent({
    required this.onProtectedAction,
    required this.onEditProfile,
    required this.onOrders,
    required this.onMap,
    required this.onFavorites,
    required this.onAboutUs,
    required this.onShareApp,
    required this.onLogout,
  });

  @override
  State<_ProfileXdContent> createState() => _ProfileXdContentState();
}

class _ProfileXdContentState extends State<_ProfileXdContent> {
  late final Future<_StoredUserProfile> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _StoredUserProfile.load();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(height: 126, color: MerzoxColors.kColor95BDD5),
        const Positioned(
          top: 28,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              'الملف الشخصي',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        ListView(
          padding: const EdgeInsets.fromLTRB(4, 78, 4, 118),
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 34),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              ),
              child: Column(
                children: [
                  const _ProfileXdAvatar(),
                  const SizedBox(height: 5),
                  FutureBuilder<_StoredUserProfile>(
                    future: _profileFuture,
                    builder: (context, snapshot) {
                      final name = snapshot.data?.name ?? 'مستخدم Merzox';

                      return Text(
                        '$name ، أهلا',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF2B2B2B),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  _ProfileMerchantButton(onPressed: widget.onProtectedAction),
                  const SizedBox(height: 18),
                  _ProfileXdMenuTile(
                    title: 'تعديل الملف الشخصي',
                    icon: Icons.edit_outlined,
                    onTap: widget.onEditProfile,
                  ),
                  _ProfileXdMenuTile(
                    title: 'طلباتي',
                    icon: Icons.article_outlined,
                    onTap: widget.onOrders,
                  ),
                  _ProfileXdMenuTile(
                    title: 'الخريطة',
                    icon: Icons.location_on_outlined,
                    onTap: widget.onMap,
                  ),
                  _ProfileXdMenuTile(
                    title: 'المفضلة',
                    icon: Icons.favorite_border_rounded,
                    onTap: widget.onFavorites,
                  ),
                  _ProfileXdMenuTile(
                    title: 'aboutUs.title'.tr(),
                    icon: Icons.info_outline_rounded,
                    onTap: widget.onAboutUs,
                  ),
                  const NotificationPreferenceControl(),
                  _ProfileXdMenuTile(
                    title: 'shareApp.profileTitle'.tr(),
                    icon: Icons.ios_share_rounded,
                    onTap: widget.onShareApp,
                  ),
                  const SizedBox(height: 44),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _ProfileSocialButton(
                        icon: Icons.camera_alt_outlined,
                        label: 'Instagram',
                      ),
                      SizedBox(width: 10),
                      _ProfileSocialButton(
                        icon: Icons.facebook_rounded,
                        label: 'Facebook',
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _ProfileXdLogoutButton(onPressed: widget.onLogout),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileXdAvatar extends StatelessWidget {
  const _ProfileXdAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: MerzoxColors.kColorD8D8D8),
      ),
      child: CircleAvatar(backgroundColor: MerzoxColors.kColorBEBEBE),
    );
  }
}

class _ProfileMerchantButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ProfileMerchantButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 120,
      height: 42,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.storefront_outlined, size: 16),
        label: const Text(
          'التسجيل كتاجر',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: MerzoxColors.kColor3D5A80,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }
}

class _ProfileXdMenuTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _ProfileXdMenuTile({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF5F9FC,
        borderRadius: BorderRadius.circular(4),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                Icons.chevron_left_rounded,
                color: MerzoxColors.kColor3D5A80,
                size: 18,
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(fontSize: 12, color: Color(0xFF2B2B2B)),
              ),
              const SizedBox(width: 12),
              Icon(icon, color: MerzoxColors.kColor3D5A80, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileSocialButton extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ProfileSocialButton({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      button: true,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: MerzoxColors.kColor3D5A80,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}

class _ProfileXdLogoutButton extends StatelessWidget {
  final VoidCallback onPressed;

  const _ProfileXdLogoutButton({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: TextButton.icon(
        onPressed: onPressed,
        icon: Icon(
          Icons.logout_rounded,
          color: MerzoxColors.kColor3D5A80,
          size: 18,
        ),
        label: const Text('تسجيل خروج', style: TextStyle(fontSize: 12)),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF2B2B2B),
          backgroundColor: MerzoxColors.kColorF5F9FC,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
      ),
    );
  }
}

class _EmptyFeatureState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyFeatureState({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MerzoxColors.kColorF9F9F9,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 42, color: MerzoxColors.kColor98C1D9),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: MerzoxColors.kColor767676,
            ),
          ),
        ],
      ),
    );
  }
}

class _CartSummaryCard extends StatelessWidget {
  final double subtotal;
  final VoidCallback? onCheckoutPressed;

  const _CartSummaryCard({
    required this.subtotal,
    required this.onCheckoutPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MerzoxColors.kColorEFEFEF),
      ),
      child: Column(
        children: [
          _SummaryRow(
            label: 'المجموع الفرعي',
            value: '\u20AA ${subtotal.toStringAsFixed(0)}',
          ),
          const SizedBox(height: 8),
          _SummaryRow(label: 'التوصيل', value: 'يحسب لاحقا'),
          const Divider(height: 24),
          _SummaryRow(
            label: 'الإجمالي',
            value: '\u20AA ${subtotal.toStringAsFixed(0)}',
            isStrong: true,
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onCheckoutPressed,
            style: FilledButton.styleFrom(
              backgroundColor: MerzoxColors.kColorEE6C4D,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(46),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('إكمال الطلب'),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isStrong;

  const _SummaryRow({
    required this.label,
    required this.value,
    this.isStrong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isStrong ? 15 : 13,
            fontWeight: isStrong ? FontWeight.w800 : FontWeight.w500,
            color: const Color(0xFF2B2B2B),
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: isStrong ? 15 : 13,
            fontWeight: isStrong ? FontWeight.w800 : FontWeight.w600,
            color: isStrong
                ? MerzoxColors.kColorEE6C4D
                : MerzoxColors.kColor767676,
          ),
        ),
      ],
    );
  }
}

void _openBusinessProfile(BuildContext context, HomeBusiness business) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (routeContext) {
        return Directionality(
          textDirection: Directionality.of(context),
          child: BusinessProfilePage(
            business: business,
            onNavChanged: (index) {
              Navigator.of(routeContext).pop();
              if (index != 0 && context.mounted) {
                context.read<HomeBloc>().add(HomeTabChanged(index));
              }
            },
          ),
        );
      },
    ),
  );
}

// ignore: unused_element
class _BusinessProfileTopBar extends StatelessWidget {
  final VoidCallback onBack;

  const _BusinessProfileTopBar({required this.onBack});

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return SizedBox(
      height: 42,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              tooltip: 'رجوع',
              onPressed: onBack,
              icon: Icon(
                isRtl
                    ? Icons.chevron_right_rounded
                    : Icons.chevron_left_rounded,
                size: 34,
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  size: 22,
                  color: MerzoxColors.kColor98C1D9,
                ),
                PositionedDirectional(
                  top: 1,
                  end: -1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: MerzoxColors.kColorEE6C4D,
                      shape: BoxShape.circle,
                    ),
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

class _ComingSoonTab extends StatelessWidget {
  final int index;

  const _ComingSoonTab({required this.index});

  @override
  Widget build(BuildContext context) {
    final titles = ['الرئيسية', 'المتاجر', 'الطلبات', 'الرسائل', 'الحساب'];

    return Center(
      child: Text(
        '${titles[index]} قريباً',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    );
  }
}
