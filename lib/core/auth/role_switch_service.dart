import 'package:shared_preferences/shared_preferences.dart';

import '../../features/authentication/bloc/auth_bloc.dart';
import 'auth_session_service.dart';

/// Which way round one account is being used.
///
/// A shopkeeper buys from other shopkeepers. The account does not change when
/// they do - the same person, the same login - only the way the app is being
/// used, so this is a role the reader turns rather than a second account they
/// sign in to.
enum MerzoxRole { customer, merchant }

/// Turning between the two.
///
/// Two facts used to live in one stored value: what the account IS, and how it
/// is being used. Keeping them apart is what makes the turn possible - and
/// what makes the one rule enforceable, that a reader may only take the
/// merchant side of an account that actually owns a shop.
class RoleSwitchService {
  final AuthSessionService _session;

  const RoleSwitchService({
    AuthSessionService session = const AuthSessionService(),
  }) : _session = session;

  /// Puts the app on the customer side. Always allowed: anyone may shop.
  Future<void> actAsCustomer() => _write(MerzoxRole.customer);

  /// Puts the app on the merchant side.
  ///
  /// Refused unless the account owns a shop. The way to own one is the
  /// enrolment on the customer home screen, and that is deliberately the only
  /// way in - a switch that could conjure a merchant would make the enrolment
  /// optional, and with it everything enrolment asks for.
  ///
  /// Returns whether the turn was made.
  Future<bool> actAsMerchant() async {
    final AuthSessionSnapshot session = await _session.read();

    if (!session.ownsBusiness) return false;

    await _write(MerzoxRole.merchant);
    return true;
  }

  Future<void> _write(MerzoxRole role) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(AuthBloc.activeRoleKey, roleName(role));
  }
}

/// How the account type of a shop owner is spelled in storage.
const String kBusinessAccountType = 'business';

/// Whether an account owns a shop, read from its stored account type.
///
/// The one gate on the merchant side, and the reason the switch cannot stand
/// in for enrolment: only enrolling writes this value.
bool accountOwnsBusiness(String? userType) =>
    userType?.trim() == kBusinessAccountType;

/// How a role is spelled in storage.
String roleName(MerzoxRole role) =>
    role == MerzoxRole.merchant ? 'merchant' : 'customer';

/// Which side the app is on, given what the account is and what was last
/// chosen.
///
/// An account that owns no shop is always on the customer side, whatever a
/// stored value says: a value left behind by an account that did own one, or
/// edited on the device, must not hand out a merchant session.
MerzoxRole activeRoleFor({required bool ownsBusiness, String? stored}) {
  if (!ownsBusiness) return MerzoxRole.customer;

  // A shop owner who has not chosen starts where their account puts them.
  if (stored == null || stored.trim().isEmpty) return MerzoxRole.merchant;

  return stored.trim() == roleName(MerzoxRole.customer)
      ? MerzoxRole.customer
      : MerzoxRole.merchant;
}
