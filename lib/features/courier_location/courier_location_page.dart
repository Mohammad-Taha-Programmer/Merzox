import 'package:easy_localization/easy_localization.dart' hide TextDirection;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../core/constants/colors.dart';
import '../../core/localization/api_error_localizer.dart';
import 'courier_location_bloc.dart';

bool shouldStopCourierLocationForLifecycle(AppLifecycleState state) {
  return state == AppLifecycleState.hidden ||
      state == AppLifecycleState.paused ||
      state == AppLifecycleState.detached;
}

class CourierLocationPage extends StatefulWidget {
  const CourierLocationPage({super.key});

  @override
  State<CourierLocationPage> createState() => _CourierLocationPageState();
}

class _CourierLocationPageState extends State<CourierLocationPage>
    with WidgetsBindingObserver {
  final _orderIdController = TextEditingController();
  final _capabilityController = TextEditingController();

  bool _showCapability = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!shouldStopCourierLocationForLifecycle(state)) {
      return;
    }

    _capabilityController.clear();

    if (mounted) {
      context.read<CourierLocationBloc>().add(
        const CourierLocationStopRequested(),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    _orderIdController.dispose();
    _capabilityController.dispose();

    super.dispose();
  }

  void _start() {
    context.read<CourierLocationBloc>().add(
      CourierLocationStartRequested(
        orderId: _orderIdController.text,
        capabilityToken: _capabilityController.text,
      ),
    );
  }

  void _stop() {
    _capabilityController.clear();

    context.read<CourierLocationBloc>().add(
      const CourierLocationStopRequested(),
    );
  }

  String _errorText(String value) {
    if (value.startsWith('courierLocation.')) {
      return value.tr();
    }

    return localizeApiErrorOrRaw(value);
  }

  String? _statusText(CourierLocationState state) {
    return switch (state.status) {
      CourierLocationStatus.initial => null,
      CourierLocationStatus.checking => 'courierLocation.checking'.tr(),
      CourierLocationStatus.sharing => 'courierLocation.sharing'.tr(),
      CourierLocationStatus.stopped => 'courierLocation.stopped'.tr(),
      CourierLocationStatus.serviceDisabled =>
        'courierLocation.serviceDisabled'.tr(),
      CourierLocationStatus.permissionDenied =>
        'courierLocation.permissionDenied'.tr(),
      CourierLocationStatus.permissionDeniedForever =>
        'courierLocation.permissionDeniedForever'.tr(),
      CourierLocationStatus.failure => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: MerzoxColors.kColor2B2B2B,
        elevation: 0,
        title: Text(
          'courierLocation.title'.tr(),
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: BlocConsumer<CourierLocationBloc, CourierLocationState>(
        listenWhen: (previous, current) =>
            !previous.hasUploaded && current.hasUploaded,
        listener: (_, __) {
          // After the backend has accepted the first location snapshot,
          // the visible input no longer needs to retain the capability.
          _capabilityController.clear();
        },
        builder: (context, state) {
          final active = state.isActive;
          final statusText = _statusText(state);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            children: [
              Text(
                'courierLocation.subtitle'.tr(),
                style: const TextStyle(
                  color: MerzoxColors.kColor5E5E5E,
                  fontSize: 14,
                  height: 1.55,
                ),
              ),
              const SizedBox(height: 22),
              TextField(
                controller: _orderIdController,
                enabled: !active,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'courierLocation.orderId'.tr(),
                  hintText: 'courierLocation.orderIdHint'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _capabilityController,
                enabled: !active,
                autocorrect: false,
                enableSuggestions: false,
                obscureText: !_showCapability,
                keyboardType: TextInputType.visiblePassword,
                decoration: InputDecoration(
                  labelText: 'courierLocation.accessCode'.tr(),
                  hintText: 'courierLocation.accessCodeHint'.tr(),
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: _showCapability
                        ? 'auth.hidePassword'.tr()
                        : 'auth.showPassword'.tr(),
                    onPressed: active
                        ? null
                        : () {
                            setState(() {
                              _showCapability = !_showCapability;
                            });
                          },
                    icon: Icon(
                      _showCapability
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (state.status == CourierLocationStatus.checking)
                const Center(child: CircularProgressIndicator())
              else if (state.status == CourierLocationStatus.sharing)
                FilledButton.icon(
                  onPressed: _stop,
                  style: FilledButton.styleFrom(
                    backgroundColor: MerzoxColors.kColorEE6C4D,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: Text('courierLocation.stop'.tr()),
                )
              else
                FilledButton.icon(
                  onPressed: _start,
                  style: FilledButton.styleFrom(
                    backgroundColor: MerzoxColors.kColor3D5A80,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  icon: const Icon(Icons.my_location_rounded),
                  label: Text('courierLocation.start'.tr()),
                ),
              if (statusText != null) ...[
                const SizedBox(height: 16),
                Text(
                  statusText,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MerzoxColors.kColor5E5E5E,
                    fontSize: 13,
                  ),
                ),
              ],
              if (state.errorMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  _errorText(state.errorMessage),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MerzoxColors.kColorEE6C4D,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (state.lastUploadedAt != null) ...[
                const SizedBox(height: 14),
                Text(
                  'courierLocation.lastSent'.tr(
                    args: [state.lastUploadedAt!.toLocal().toIso8601String()],
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: MerzoxColors.kColor767676,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 26),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MerzoxColors.kColorF5F9FC,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: MerzoxColors.kColorDEEEF8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.privacy_tip_outlined,
                      color: MerzoxColors.kColor3D5A80,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'courierLocation.privacy'.tr(),
                        style: const TextStyle(
                          color: MerzoxColors.kColor5E5E5E,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
