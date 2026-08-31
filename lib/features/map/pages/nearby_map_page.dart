import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';

import '../../../core/constants/colors.dart';
import '../../../services/api_service.dart';
import '../../business_profile/pages/business_profile_page.dart';
import '../../home/presentation/bloc/home_state_.dart';
import '../bloc/nearby_map_bloc.dart';
import '../bloc/nearby_map_event.dart';
import '../bloc/nearby_map_state.dart';

class NearbyMapPage extends StatefulWidget {
  const NearbyMapPage({super.key});

  @override
  State<NearbyMapPage> createState() => _NearbyMapPageState();
}

class _NearbyMapPageState extends State<NearbyMapPage> {
  final MapController _mapController = MapController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _submitSearch() {
    FocusScope.of(context).unfocus();
    context.read<NearbyMapBloc>().add(
      NearbyMapSearchSubmitted(_searchController.text),
    );
  }

  void _selectBusiness(SearchBusinessApiModel business) {
    context.read<NearbyMapBloc>().add(NearbyMapBusinessSelected(business.id));
    final latitude = business.latitude;
    final longitude = business.longitude;
    if (latitude != null && longitude != null) {
      _mapController.move(LatLng(latitude, longitude), 15.5);
    }
  }

  Future<void> _openDirections(SearchBusinessApiModel business) async {
    final latitude = business.latitude;
    final longitude = business.longitude;
    if (latitude == null || longitude == null) return;

    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '$latitude,$longitude',
      'travelmode': 'driving',
    });
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('map.directionsError'.tr())));
    }
  }

  Future<void> _openBusinessProfile(SearchBusinessApiModel business) async {
    final homeBusiness = HomeBusiness.fromApi(business);

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => BusinessProfilePage(
          business: homeBusiness,
          onNavChanged: (index) {
            Navigator.of(context).pop();
            context.go('/home?tab=$index');
          },
        ),
      ),
    );
  }

  void _recenter(NearbyMapState state) {
    final latitude = state.userLatitude;
    final longitude = state.userLongitude;
    if (latitude == null || longitude == null) return;
    _mapController.move(LatLng(latitude, longitude), 14.5);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: BlocConsumer<NearbyMapBloc, NearbyMapState>(
          listenWhen: (previous, current) {
            return current.userLatitude != null &&
                current.userLongitude != null &&
                (previous.userLatitude != current.userLatitude ||
                    previous.userLongitude != current.userLongitude);
          },
          listener: (context, state) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _recenter(state);
            });
          },
          builder: (context, state) {
            return Column(
              children: [
                const _MapHeader(),
                Expanded(child: _buildBody(state)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildBody(NearbyMapState state) {
    switch (state.status) {
      case NearbyMapStatus.initial:
      case NearbyMapStatus.checkingPermission:
        return const Center(
          child: CircularProgressIndicator(color: MerzoxColors.kColor3D5A80),
        );
      case NearbyMapStatus.permissionRequired:
        return _LocationGate(
          icon: Icons.location_on_outlined,
          title: 'map.allowLocationTitle'.tr(),
          body: 'map.allowLocationBody'.tr(),
          primaryLabel: 'map.allowLocation'.tr(),
          onPrimary: () => context.read<NearbyMapBloc>().add(
            const NearbyMapPermissionRequested(),
          ),
        );
      case NearbyMapStatus.permissionPermanentlyDenied:
        return _LocationGate(
          icon: Icons.location_off_outlined,
          title: 'map.allowLocationTitle'.tr(),
          body: 'map.allowLocationBody'.tr(),
          primaryLabel: 'map.openSettings'.tr(),
          onPrimary: () => context.read<NearbyMapBloc>().add(
            const NearbyMapAppSettingsRequested(),
          ),
          secondaryLabel: 'common.retry'.tr(),
          onSecondary: () =>
              context.read<NearbyMapBloc>().add(const NearbyMapRefreshed()),
        );
      case NearbyMapStatus.locationServiceDisabled:
        return _LocationGate(
          icon: Icons.gps_off_rounded,
          title: 'map.serviceDisabledTitle'.tr(),
          body: 'map.serviceDisabledBody'.tr(),
          primaryLabel: 'map.openSettings'.tr(),
          onPrimary: () => context.read<NearbyMapBloc>().add(
            const NearbyMapLocationSettingsRequested(),
          ),
          secondaryLabel: 'common.retry'.tr(),
          onSecondary: () =>
              context.read<NearbyMapBloc>().add(const NearbyMapRefreshed()),
        );
      case NearbyMapStatus.failure:
        return _LocationGate(
          icon: Icons.map_outlined,
          title: 'map.loadError'.tr(),
          body: localizeApiErrorOrRaw(state.errorMessage),
          primaryLabel: 'common.retry'.tr(),
          onPrimary: () =>
              context.read<NearbyMapBloc>().add(const NearbyMapRefreshed()),
        );
      case NearbyMapStatus.loading:
        if (state.userLatitude == null || state.userLongitude == null) {
          return const Center(
            child: CircularProgressIndicator(color: MerzoxColors.kColor3D5A80),
          );
        }
        return _buildMap(state, loading: true);
      case NearbyMapStatus.ready:
        return _buildMap(state);
    }
  }

  Widget _buildMap(NearbyMapState state, {bool loading = false}) {
    final userPoint = LatLng(state.userLatitude!, state.userLongitude!);
    final selectedBusiness = state.selectedBusiness;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: userPoint,
                initialZoom: 14.5,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onTap: (_, __) => context.read<NearbyMapBloc>().add(
                  const NearbyMapBusinessSelected(''),
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.merzox',
                  maxNativeZoom: 19,
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: userPoint,
                      width: 54,
                      height: 54,
                      child: const _UserLocationMarker(),
                    ),
                    ...state.businesses.map(
                      (business) => Marker(
                        point: LatLng(business.latitude!, business.longitude!),
                        width: 104,
                        height: 88,
                        alignment: Alignment.topCenter,
                        child: _BusinessMapMarker(
                          selected: business.id == state.selectedBusinessId,
                          name: business.name,
                          onTap: () => _selectBusiness(business),
                        ),
                      ),
                    ),
                  ],
                ),
                RichAttributionWidget(
                  showFlutterMapAttribution: false,
                  attributions: [
                    TextSourceAttribution(
                      'OpenStreetMap contributors',
                      onTap: () => launchUrl(
                        Uri.parse('https://www.openstreetmap.org/copyright'),
                        mode: LaunchMode.externalApplication,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            PositionedDirectional(
              top: 14,
              start: 12,
              end: 12,
              child: _MapSearchField(
                controller: _searchController,
                onSubmitted: _submitSearch,
              ),
            ),
            if (state.businesses.isNotEmpty)
              PositionedDirectional(
                top: 76,
                start: 12,
                end: 12,
                child: _MapBusinessResults(
                  businesses: state.businesses,
                  selectedBusinessId: state.selectedBusinessId,
                  onSelected: _selectBusiness,
                ),
              ),
            PositionedDirectional(
              end: 12,
              bottom: selectedBusiness == null ? 22 : 180,
              child: FloatingActionButton.small(
                heroTag: 'merzox-map-location',
                tooltip: 'map.myLocation'.tr(),
                onPressed: () => _recenter(state),
                backgroundColor: Colors.white,
                foregroundColor: MerzoxColors.kColor3D5A80,
                child: const Icon(Icons.my_location_rounded),
              ),
            ),
            if (selectedBusiness != null)
              PositionedDirectional(
                start: 12,
                end: 12,
                bottom: 14,
                child: _SelectedBusinessCard(
                  business: selectedBusiness,
                  onProfile: () => _openBusinessProfile(selectedBusiness),
                  onDirections: () => _openDirections(selectedBusiness),
                ),
              ),
            if (state.businesses.isEmpty && !loading)
              PositionedDirectional(
                start: 28,
                end: 28,
                top: 146,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 10,
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'map.noBusinesses'.tr(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: MerzoxColors.kColor3B3B3B,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
              ),
            if (loading)
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  color: MerzoxColors.kColorEE6C4D,
                  backgroundColor: Colors.transparent,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MapHeader extends StatelessWidget {
  const _MapHeader();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 82,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            'map.title'.tr(),
            style: const TextStyle(
              color: MerzoxColors.kColor2B2B2B,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          PositionedDirectional(
            start: 8,
            child: const BackButton(color: MerzoxColors.kColor5E5E5E),
          ),
        ],
      ),
    );
  }
}

class _MapSearchField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmitted;

  const _MapSearchField({required this.controller, required this.onSubmitted});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 50,
        child: TextField(
          controller: controller,
          textInputAction: TextInputAction.search,
          onSubmitted: (_) => onSubmitted(),
          decoration: InputDecoration(
            hintText: 'map.searchHint'.tr(),
            hintStyle: const TextStyle(
              color: MerzoxColors.kColorBEBEBE,
              fontSize: 13,
            ),
            prefixIcon: IconButton(
              tooltip: 'common.search'.tr(),
              onPressed: onSubmitted,
              icon: const Icon(
                Icons.search_rounded,
                color: MerzoxColors.kColor3D5A80,
              ),
            ),
            suffixIcon: ValueListenableBuilder<TextEditingValue>(
              valueListenable: controller,
              builder: (context, value, _) {
                if (value.text.isEmpty) return const SizedBox.shrink();
                return IconButton(
                  tooltip: 'common.cancel'.tr(),
                  onPressed: () {
                    controller.clear();
                    onSubmitted();
                  },
                  icon: const Icon(Icons.close_rounded, size: 20),
                );
              },
            ),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
          ),
        ),
      ),
    );
  }
}

class _MapBusinessResults extends StatelessWidget {
  final List<SearchBusinessApiModel> businesses;
  final String selectedBusinessId;
  final ValueChanged<SearchBusinessApiModel> onSelected;

  const _MapBusinessResults({
    required this.businesses,
    required this.selectedBusinessId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: businesses.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, index) {
          final business = businesses[index];
          final selected = business.id == selectedBusinessId;
          return ChoiceChip(
            selected: selected,
            onSelected: (_) => onSelected(business),
            avatar: Icon(
              Icons.storefront_outlined,
              size: 17,
              color: selected ? Colors.white : MerzoxColors.kColor3D5A80,
            ),
            label: Text(
              business.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            labelStyle: TextStyle(
              color: selected ? Colors.white : MerzoxColors.kColor3B3B3B,
              fontSize: 11,
            ),
            backgroundColor: Colors.white,
            selectedColor: MerzoxColors.kColor3D5A80,
            side: BorderSide(
              color: selected
                  ? MerzoxColors.kColor3D5A80
                  : MerzoxColors.kColorDEEEF8,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
          );
        },
      ),
    );
  }
}

class _UserLocationMarker extends StatelessWidget {
  const _UserLocationMarker();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: const Color(0xFF3F91E8),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF3F91E8).withValues(alpha: 0.35),
              blurRadius: 12,
              spreadRadius: 5,
            ),
          ],
        ),
      ),
    );
  }
}

class _BusinessMapMarker extends StatelessWidget {
  final bool selected;
  final String name;
  final VoidCallback onTap;

  const _BusinessMapMarker({
    required this.selected,
    required this.name,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? MerzoxColors.kColorEE6C4D
        : MerzoxColors.kColor3D5A80;

    // `الخريطة` writes each shop's name beside its pin. It used to live in a
    // `Tooltip`, which on a phone means nobody reads it - and which also hung
    // any attempt to capture this screen, because a tooltip keeps a timer
    // alive and the capture waits for the timers to drain.
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: selected ? 43 : 38,
            height: selected ? 43 : 38,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.storefront_outlined,
              color: Colors.white,
              size: 21,
            ),
          ),
          CustomPaint(
            size: const Size(12, 8),
            painter: _MarkerTailPainter(color),
          ),
          const SizedBox(height: 4),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x1F000000),
                    blurRadius: 6,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? MerzoxColors.kColorEE6C4D
                      : MerzoxColors.kColor2B2B2B,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MarkerTailPainter extends CustomPainter {
  final Color color;

  const _MarkerTailPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final path = ui.Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _MarkerTailPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _SelectedBusinessCard extends StatelessWidget {
  final SearchBusinessApiModel business;
  final VoidCallback onProfile;
  final VoidCallback onDirections;

  const _SelectedBusinessCard({
    required this.business,
    required this.onProfile,
    required this.onDirections,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 5,
      borderRadius: BorderRadius.circular(7),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Color(business.colorValue),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: const Icon(
                    Icons.storefront_outlined,
                    color: MerzoxColors.kColor3D5A80,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        business.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: MerzoxColors.kColor2B2B2B,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          business.category,
                          _distanceText(business.distanceMeters),
                        ].where((part) => part.isNotEmpty).join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: MerzoxColors.kColor707070,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (business.address.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                business.address,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: MerzoxColors.kColor5E5E5E,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onProfile,
                    icon: const Icon(Icons.storefront_outlined, size: 18),
                    label: Text('map.profile'.tr()),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MerzoxColors.kColor3D5A80,
                      side: const BorderSide(color: MerzoxColors.kColor98C1D9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onDirections,
                    icon: const Icon(Icons.directions_outlined, size: 18),
                    label: Text('map.directions'.tr()),
                    style: FilledButton.styleFrom(
                      backgroundColor: MerzoxColors.kColorEE6C4D,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationGate extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  const _LocationGate({
    required this.icon,
    required this.title,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 108,
              height: 108,
              decoration: const BoxDecoration(
                color: MerzoxColors.kColorEEF6FB,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 54, color: MerzoxColors.kColor3D5A80),
            ),
            const SizedBox(height: 28),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MerzoxColors.kColor2B2B2B,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: MerzoxColors.kColor707070,
                fontSize: 13,
                height: 1.6,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 224,
              height: 48,
              child: FilledButton(
                onPressed: onPrimary,
                style: FilledButton.styleFrom(
                  backgroundColor: MerzoxColors.kColorEE6C4D,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
                child: Text(
                  primaryLabel,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (secondaryLabel != null && onSecondary != null) ...[
              const SizedBox(height: 10),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

String _distanceText(int? distanceMeters) {
  if (distanceMeters == null) return '';
  if (distanceMeters < 1000) {
    return 'map.distanceMeters'.tr(args: ['$distanceMeters']);
  }
  final kilometers = distanceMeters / 1000;
  final value = kilometers < 10
      ? kilometers.toStringAsFixed(1)
      : kilometers.toStringAsFixed(0);
  return 'map.distanceKilometers'.tr(args: [value]);
}
