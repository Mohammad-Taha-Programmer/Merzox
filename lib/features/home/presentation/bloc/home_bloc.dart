import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:merzox/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'home_event.dart';
import 'home_state_.dart';

class HomeBloc extends Bloc<HomeEvent, HomeState> {
  final ApiService _apiService;

  HomeBloc({ApiService? apiService})
    : _apiService = apiService ?? ApiService(),
      super(const HomeState()) {
    on<HomeStarted>(_onStarted);
    on<HomeSearchChanged>(_onSearchChanged);
    on<HomeTabChanged>(_onTabChanged);
    on<HomeLocationPromptShown>(_onLocationPromptShown);
    on<HomeLocationServiceRequested>(_onLocationServiceRequested);
    on<HomeLocationPermissionAnswered>(_onLocationPermissionAnswered);
    on<HomeBusinessFollowToggled>(_onBusinessFollowToggled);
    on<HomeAllBusinessesNextPageRequested>(_onAllBusinessesNextPageRequested);
  }

  Future<void> _onStarted(HomeStarted event, Emitter<HomeState> emit) async {
    final prefs = await SharedPreferences.getInstance();
    final shouldAskAfterLogin =
        !event.isGuest &&
        (prefs.getBool(AuthBloc.locationPromptPendingKey) ?? false);
    final granted =
        prefs.getBool(AuthBloc.locationPermissionGrantedKey) ?? false;

    emit(
      state.copyWith(
        selectedTab: event.initialTab.clamp(0, 4),
        newBusinesses: _newBusinesses,
        bestBusinesses: _bestBusinesses,
        discountedBusinesses: _discountedBusinesses,
        nearbyBusinesses: _nearbyBusinesses,
        allBusinesses: _allBusinesses.take(_allBusinessesPageSize).toList(),
        allBusinessesPage: 1,
        hasMoreAllBusinesses: _allBusinesses.length > _allBusinessesPageSize,
        shouldAskLocationPermission: shouldAskAfterLogin,
        locationPermissionHandled: !shouldAskAfterLogin,
        locationPermissionGranted: granted,
        locationPermissionReason: 'firstLogin',
      ),
    );

    if (!event.isGuest) {
      final token = prefs.getString(AuthBloc.tokenKey);
      if (token != null && token.isNotEmpty) {
        try {
          final response = await _apiService.favoriteBusinesses(
            token: token,
            limit: 100,
          );
          final followedIds = <String>{};
          for (final business in response.businesses) {
            followedIds.add(business.id);
            if (business.publicId.isNotEmpty) {
              followedIds.add(business.publicId);
            }
          }
          emit(state.copyWith(followedBusinessIds: followedIds));
        } catch (_) {
          // The home page remains usable while favorites are temporarily offline.
        }
      }
    }
  }

  void _onSearchChanged(HomeSearchChanged event, Emitter<HomeState> emit) {
    emit(state.copyWith(searchQuery: event.query));
  }

  void _onTabChanged(HomeTabChanged event, Emitter<HomeState> emit) {
    var nextState = state.copyWith(selectedTab: event.index);

    if (event.index == 2 && nextState.allBusinesses.isEmpty) {
      nextState = nextState.copyWith(
        allBusinesses: _allBusinesses.take(_allBusinessesPageSize).toList(),
        allBusinessesPage: 1,
        hasMoreAllBusinesses: _allBusinesses.length > _allBusinessesPageSize,
      );
    }

    emit(nextState);
  }

  void _onLocationPromptShown(
    HomeLocationPromptShown event,
    Emitter<HomeState> emit,
  ) {
    emit(state.copyWith(shouldAskLocationPermission: false));
  }

  void _onLocationServiceRequested(
    HomeLocationServiceRequested event,
    Emitter<HomeState> emit,
  ) {
    if (state.locationPermissionGranted) {
      return;
    }

    emit(
      state.copyWith(
        shouldAskLocationPermission: true,
        locationPermissionReason: event.reason,
      ),
    );
  }

  Future<void> _onLocationPermissionAnswered(
    HomeLocationPermissionAnswered event,
    Emitter<HomeState> emit,
  ) async {
    await _persistLocationPermission(granted: event.granted);

    emit(
      state.copyWith(
        locationPermissionHandled: true,
        locationPermissionGranted: event.granted,
        locationPermissionPermanentlyDenied: false,
        shouldAskLocationPermission: false,
      ),
    );
  }

  Future<void> _persistLocationPermission({required bool granted}) async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString(AuthBloc.userIdKey);
    final token = prefs.getString(AuthBloc.tokenKey);

    await prefs.setBool(AuthBloc.locationPermissionGrantedKey, granted);
    await prefs.setBool(AuthBloc.locationPromptPendingKey, false);

    if (userId != null && userId.isNotEmpty) {
      await prefs.setBool('${AuthBloc.locationPromptAskedPrefix}$userId', true);
    }

    if (token != null && token.isNotEmpty) {
      try {
        await _apiService.updatePermissions(token: token, location: granted);
      } catch (_) {
        // Local consent is kept even if the sync is temporarily unavailable.
      }
    }
  }

  Future<void> _onBusinessFollowToggled(
    HomeBusinessFollowToggled event,
    Emitter<HomeState> emit,
  ) async {
    final followedIds = Set<String>.from(state.followedBusinessIds);
    final wasFollowed = followedIds.contains(event.businessId);

    if (wasFollowed) {
      followedIds.remove(event.businessId);
    } else {
      followedIds.add(event.businessId);
    }

    emit(state.copyWith(followedBusinessIds: followedIds));

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(AuthBloc.tokenKey);
      if (token == null || token.isEmpty) {
        throw StateError('Authentication required');
      }
      await _apiService.setBusinessFavorited(
        token: token,
        businessId: event.businessId,
        favorited: !wasFollowed,
      );
    } catch (_) {
      final reverted = Set<String>.from(state.followedBusinessIds);
      if (wasFollowed) {
        reverted.add(event.businessId);
      } else {
        reverted.remove(event.businessId);
      }
      emit(state.copyWith(followedBusinessIds: reverted));
    }
  }

  void _onAllBusinessesNextPageRequested(
    HomeAllBusinessesNextPageRequested event,
    Emitter<HomeState> emit,
  ) {
    if (state.isLoadingAllBusinesses || !state.hasMoreAllBusinesses) {
      return;
    }

    emit(state.copyWith(isLoadingAllBusinesses: true));

    final start = state.allBusinessesPage * _allBusinessesPageSize;
    final nextBusinesses = _allBusinesses
        .skip(start)
        .take(_allBusinessesPageSize)
        .toList();
    final loadedBusinesses = [...state.allBusinesses, ...nextBusinesses];

    emit(
      state.copyWith(
        allBusinesses: loadedBusinesses,
        allBusinessesPage: state.allBusinessesPage + 1,
        isLoadingAllBusinesses: false,
        hasMoreAllBusinesses: loadedBusinesses.length < _allBusinesses.length,
      ),
    );
  }
}

const int _allBusinessesPageSize = 100;

final List<HomeBusiness> _allBusinesses = List.unmodifiable([
  ..._newBusinesses,
  ..._bestBusinesses,
  ..._discountedBusinesses,
  ..._nearbyBusinesses,
  ...List.generate(238, (index) {
    final serial = index + 1;
    final names = [
      'متجر الياسمين',
      'مخبز المدينة',
      'خضار المدينة',
      'مكتبة الساحل',
      'صيدلية النور',
      'زهور الربيع',
    ];
    final categories = [
      'مواد غذائية',
      'مخبوزات',
      'خضار وفواكه',
      'قرطاسية وهدايا',
      'صحة وعناية',
      'هدايا وزهور',
    ];
    final products = [
      ['ألبان', 'قهوة', 'خضار'],
      ['خبز', 'كعك', 'معجنات'],
      ['فواكه', 'خضار', 'عصائر'],
      ['دفاتر', 'أقلام', 'هدايا'],
      ['دواء', 'فيتامينات', 'عناية'],
      ['ورد', 'شوكولاتة', 'هدايا'],
    ];
    final colors = [0xFFDEEEF8, 0xFFF3EBB9, 0xFFBFF3B9, 0xFFB9DDF3];
    final template = index % names.length;

    return HomeBusiness(
      id: '002${(10000 + serial).toString()}',
      name: '${names[template]} ${serial.toString().padLeft(2, '0')}',
      category: categories[template],
      products: products[template],
      rating: 3.8 + (index % 12) / 10,
      distance: '${(index % 9) + 1}.${index % 10} كم',
      discount: index % 11 == 0 ? '15%' : null,
      colorValue: colors[index % colors.length],
    );
  }),
]);

const List<HomeBusiness> _newBusinesses = [
  HomeBusiness(
    id: '0020101',
    name: 'متجر الياسمين',
    category: 'مواد غذائية',
    products: ['خضار', 'ألبان', 'قهوة'],
    rating: 4.6,
    distance: '1.2 كم',
    colorValue: 0xFFDEEEF8,
  ),
  HomeBusiness(
    id: '0020102',
    name: 'صيدلية الشفاء',
    category: 'صحة وعناية',
    products: ['دواء', 'فيتامينات', 'عناية'],
    rating: 4.7,
    distance: '850 م',
    colorValue: 0xFFF3EBB9,
  ),
  HomeBusiness(
    id: '0020103',
    name: 'مخبز الدار',
    category: 'مخبوزات',
    products: ['خبز', 'كعك', 'معجنات'],
    rating: 4.5,
    distance: '2.1 كم',
    colorValue: 0xFFBFF3B9,
  ),
];

const List<HomeBusiness> _bestBusinesses = [
  HomeBusiness(
    id: '0020201',
    name: 'سوبر ماركت المدينة',
    category: 'تقييم مرتفع',
    products: ['منظفات', 'مشروبات', 'أغذية'],
    rating: 4.9,
    distance: '1.7 كم',
    colorValue: 0xFFB9DDF3,
  ),
  HomeBusiness(
    id: '0020202',
    name: 'مطعم البيت',
    category: 'وجبات وخدمات توصيل',
    products: ['وجبات', 'مشاوي', 'سلطات'],
    rating: 4.8,
    distance: '2.4 كم',
    colorValue: 0xFFC6B9F3,
  ),
  HomeBusiness(
    id: '0020203',
    name: 'مكتبة النور',
    category: 'قرطاسية وهدايا',
    products: ['دفاتر', 'أقلام', 'هدايا'],
    rating: 4.8,
    distance: '3.0 كم',
    colorValue: 0xFFF3B9B9,
  ),
];

const List<HomeBusiness> _discountedBusinesses = [
  HomeBusiness(
    id: '0020301',
    name: 'عروض الحي',
    category: 'خصومات اليوم',
    products: ['عروض', 'أدوات منزلية', 'ألعاب'],
    rating: 4.4,
    distance: '1.9 كم',
    discount: '20%',
    colorValue: 0xFFFEE3DC,
  ),
  HomeBusiness(
    id: '0020302',
    name: 'متجر الإلكترونيات',
    category: 'أجهزة واكسسوارات',
    products: ['شواحن', 'سماعات', 'هواتف'],
    rating: 4.7,
    distance: '4.1 كم',
    discount: '15%',
    colorValue: 0xFFEEF6FB,
  ),
  HomeBusiness(
    id: '0020303',
    name: 'زهور الربيع',
    category: 'هدايا وزهور',
    products: ['ورد', 'شوكولاتة', 'هدايا'],
    rating: 4.6,
    distance: '2.6 كم',
    discount: '10%',
    colorValue: 0xFFF3EBB9,
  ),
];

const List<HomeBusiness> _nearbyBusinesses = [
  HomeBusiness(
    id: '0020401',
    name: 'بقالة قريبة',
    category: 'الأقرب لك',
    products: ['ماء', 'خبز', 'حليب'],
    rating: 4.3,
    distance: '300 م',
    colorValue: 0xFFE0FBFC,
  ),
  HomeBusiness(
    id: '0020402',
    name: 'مغسلة السريع',
    category: 'خدمات يومية',
    products: ['غسيل', 'كي', 'تنظيف'],
    rating: 4.5,
    distance: '650 م',
    colorValue: 0xFFDEEEF8,
  ),
  HomeBusiness(
    id: '0020403',
    name: 'حلويات البلد',
    category: 'حلويات وطلبات',
    products: ['كنافة', 'بقلاوة', 'كيك'],
    rating: 4.6,
    distance: '900 م',
    colorValue: 0xFFF3EBB9,
  ),
];
