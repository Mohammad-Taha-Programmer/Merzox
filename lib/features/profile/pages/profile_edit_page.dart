import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/localization/language_toggle_button.dart';
import 'package:merzox/features/profile/bloc/profile_edit_bloc.dart';
import 'package:merzox/features/profile/bloc/profile_edit_event.dart';
import 'package:merzox/features/profile/bloc/profile_edit_state.dart';
import 'package:merzox/core/auth/auth_session_service.dart';
import 'package:merzox/features/checkout/pages/address_form_page.dart';
import 'package:merzox/services/api_service.dart';
import 'package:merzox/core/localization/api_error_localizer.dart';

class ProfileEditPage extends StatefulWidget {
  /// Reads and edits the account's address book. Injectable because the book
  /// is fetched by this screen rather than by the bloc behind it - the form
  /// saves the account, and an address is its own resource with its own
  /// routes.
  final ApiService? apiService;

  const ProfileEditPage({super.key, this.apiService});

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final List<_EmailFieldData> _emails = [];
  final List<_PhoneFieldData> _phones = [];

  /// The account's saved delivery addresses.
  ///
  /// Not part of the form's own save. An address is a resource of its own -
  /// created, corrected and removed through its own routes - and each of
  /// those answers with the whole book, so this holds whatever came back
  /// last rather than a copy the screen keeps in step by hand.
  List<SavedAddressApiModel> _addresses = const <SavedAddressApiModel>[];
  bool _addressesBusy = false;
  String _gender = 'female';
  bool _initialized = false;
  bool _canChangeName = true;
  bool _canChangeGender = true;

  /// The birth date is held as three independent calendar components so the
  /// XD Day / Month / Year controls stay individually selectable. It is only
  /// assembled into a canonical `YYYY-MM-DD` at submit time.
  int? _birthDay;
  int? _birthMonth;
  int? _birthYear;
  String? _initialBirthDate;
  String? _birthDateError;

  /// Drives the form, so the screen can carry the reader to its foot.
  ///
  /// A controller rather than a key on the save button, which was the first
  /// attempt: a `ListView` only attaches the children near the viewport, so
  /// on a phone - the very case this exists for - the button is not built and
  /// has no context to scroll to. The end of the list is where it sits, and
  /// the end of the list is always reachable.
  final ScrollController _formScroll = ScrollController();

  /// The form as it stood when it last agreed with the account: on opening,
  /// and again after a save. Anything that differs from this is an edit the
  /// reader has made and not yet stored.
  ///
  /// Held as one string rather than a field-by-field comparison because the
  /// question being asked is only ever "the same or not", and a comparison
  /// spread over eight fields is one somebody forgets to extend when a ninth
  /// arrives.
  String _savedShape = '';

  /// The start of the Gregorian calendar, and the only floor the year list
  /// has. It is a calendar-domain bound, not an age bound: this product has no
  /// minimum-age, adult-only or maximum-age rule, so the selector must never
  /// encode one by cutting the list off at some span of years before today.
  static const _earliestGregorianYear = 1;

  @override
  void dispose() {
    _nameController.dispose();
    _formScroll.dispose();
    for (final email in _emails) {
      email.dispose();
    }
    for (final phone in _phones) {
      phone.dispose();
    }
    super.dispose();
  }

  void _initialize(AuthApiUser user) {
    if (_initialized) {
      return;
    }

    _initialized = true;
    _adopt(user);
    _loadAddresses();
  }

  ApiService get _api => widget.apiService ?? ApiService();

  Future<String> _token() async =>
      (await const AuthSessionService().read()).token ?? '';

  Future<void> _loadAddresses() async {
    final String token = await _token();
    if (token.isEmpty) return;

    try {
      final List<SavedAddressApiModel> book = await _api.myAddresses(
        token: token,
      );
      if (mounted) setState(() => _addresses = book);
    } catch (_) {
      // The rest of the form is still editable without the book, so a failure
      // here leaves the section empty rather than taking the screen down.
    }
  }

  /// Opens the full address form.
  ///
  /// Not an inline line like the emails and the phones beside it: an address
  /// needs a name, a number, a governorate and a city, all four required, and
  /// a single text box could not collect them. What comes back is the whole
  /// book, and the row then shows the one line it reduces to.
  Future<void> _addAddress() async {
    final String token = await _token();
    if (token.isEmpty || !mounted) return;

    final List<SavedAddressApiModel>? updated =
        await Navigator.of(context).push<List<SavedAddressApiModel>>(
          MaterialPageRoute<List<SavedAddressApiModel>>(
            builder: (_) =>
                AddressFormPage(token: token, apiService: widget.apiService),
          ),
        );

    if (updated != null && mounted) setState(() => _addresses = updated);
  }

  Future<void> _removeAddress(SavedAddressApiModel entry) async {
    if (_addressesBusy) return;

    final String token = await _token();
    if (token.isEmpty || !mounted) return;

    setState(() => _addressesBusy = true);
    try {
      final List<SavedAddressApiModel> book = await _api.deleteAddress(
        token: token,
        addressId: entry.id,
      );
      if (mounted) setState(() => _addresses = book);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(ApiService.messageFromError(error).tr())),
          );
      }
    } finally {
      if (mounted) setState(() => _addressesBusy = false);
    }
  }

  /// Takes the account as the server now holds it.
  ///
  /// Read once when the screen opens, and again after a save, because the
  /// reader stays here afterwards: the one-time name and gender changes may
  /// have just been spent, and the contact lists come back normalised - lower
  /// cased, de-duplicated, the first one primary - so leaving the typed text
  /// on screen would show something other than what was stored.
  void _adopt(AuthApiUser user) {
    _canChangeName = user.canChangeName;
    _canChangeGender = user.canChangeGender;
    _nameController.text = user.name;
    _gender = user.gender == 'male' ? 'male' : 'female';

    // A legacy account carries no birth date; the three selectors then stay
    // unselected and keep showing their placeholder labels.
    final birthDate = canonicalBirthDate(user.birthDate);
    _initialBirthDate = birthDate;

    if (birthDate == null) {
      _birthYear = null;
      _birthMonth = null;
      _birthDay = null;
    } else {
      _birthYear = int.parse(birthDate.substring(0, 4));
      _birthMonth = int.parse(birthDate.substring(5, 7));
      _birthDay = int.parse(birthDate.substring(8, 10));
    }

    _birthDateError = null;

    final emails = user.emails.isNotEmpty
        ? user.emails
        : [
            if ((user.email ?? '').isNotEmpty)
              ContactEmail(value: user.email!, label: 'personal'),
          ];
    final phones = user.phones.isNotEmpty
        ? user.phones
        : [
            if ((user.phone ?? '').isNotEmpty)
              ContactPhone(value: user.phone!, label: 'mobile'),
          ];

    for (final email in _emails) {
      email.dispose();
    }
    for (final phone in _phones) {
      phone.dispose();
    }

    _emails
      ..clear()
      ..addAll(
        emails.isEmpty
            ? [_EmailFieldData()]
            : emails.map(
                (email) =>
                    _EmailFieldData(value: email.value, label: email.label),
              ),
      );
    _phones
      ..clear()
      ..addAll(
        phones.isEmpty
            ? [_PhoneFieldData()]
            : phones.map(
                (phone) =>
                    _PhoneFieldData(value: phone.value, label: phone.label),
              ),
      );

    // Taken after the fields are filled, so what is recorded is the form as
    // the account left it rather than as it was a moment earlier.
    _savedShape = _formShape();
  }

  /// Today, as a calendar day, read in UTC.
  ///
  /// The backend compares birth dates against the UTC calendar day, so the
  /// selector uses the same clock. Reading the local day instead would, for
  /// anyone ahead of UTC, offer a "today" the server still considers tomorrow
  /// and reject for a few hours around midnight.
  DateTime get _today {
    final now = DateTime.now().toUtc();
    return DateTime.utc(now.year, now.month, now.day);
  }

  int get _maxBirthMonth => _birthYear == _today.year ? _today.month : 12;

  /// The highest day the current month/year selection can legitimately offer.
  ///
  /// April stops at 30, February 2024 at 29 and February 2025 at 28. When the
  /// year is still unknown February stays open to 29 so a leap year remains
  /// reachable; the clamp below removes it again if a non-leap year follows.
  int get _maxBirthDay {
    final month = _birthMonth;

    if (month == null) {
      return 31;
    }

    final year = _birthYear;

    if (year == null) {
      return _daysInMonth(2024, month);
    }

    final inMonth = _daysInMonth(year, month);

    if (year == _today.year && month == _today.month) {
      return inMonth < _today.day ? inMonth : _today.day;
    }

    return inMonth;
  }

  /// Drops a selection that the new month/year makes impossible.
  ///
  /// Clearing is preferred over silently moving the user's chosen birthday to
  /// a neighbouring day they never picked.
  void _clampBirthSelection() {
    final month = _birthMonth;

    if (month != null && month > _maxBirthMonth) {
      _birthMonth = null;
    }

    final day = _birthDay;

    if (day != null && day > _maxBirthDay) {
      _birthDay = null;
    }
  }

  void _onBirthYearChanged(int? value) {
    setState(() {
      _birthYear = value;
      _birthDateError = null;
      _clampBirthSelection();
    });
  }

  void _onBirthMonthChanged(int? value) {
    setState(() {
      _birthMonth = value;
      _birthDateError = null;
      _clampBirthSelection();
    });
  }

  void _onBirthDayChanged(int? value) {
    setState(() {
      _birthDay = value;
      _birthDateError = null;
    });
  }

  /// The canonical `YYYY-MM-DD` for a complete selection, or null when the
  /// selection is incomplete, not a real calendar date, or in the future.
  String? _selectedBirthDate() {
    final year = _birthYear;
    final month = _birthMonth;
    final day = _birthDay;

    if (year == null || month == null || day == null) {
      return null;
    }

    final candidate = DateTime.utc(year, month, day);

    if (candidate.year != year ||
        candidate.month != month ||
        candidate.day != day ||
        candidate.isAfter(_today)) {
      return null;
    }

    return '${year.toString().padLeft(4, '0')}'
        '-${month.toString().padLeft(2, '0')}'
        '-${day.toString().padLeft(2, '0')}';
  }

  /// Everything on the form that a save would send, in one line.
  ///
  /// The addresses are deliberately absent: they are saved the moment they
  /// are added or removed, through their own routes, so they are never among
  /// the unsaved edits this screen is guarding.
  String _formShape() {
    return <String>[
      _nameController.text.trim(),
      _gender,
      _birthYear?.toString() ?? '',
      _birthMonth?.toString() ?? '',
      _birthDay?.toString() ?? '',
      for (final _EmailFieldData email in _emails)
        '${email.controller.text.trim().toLowerCase()}|${email.label}',
      for (final _PhoneFieldData phone in _phones)
        '${phone.controller.text.trim()}|${phone.label}',
    ].join('\u0000');
  }

  bool get _hasUnsavedEdits => _formShape() != _savedShape;

  /// Leaves, unless there is something unsaved to ask about first.
  ///
  /// Only no leaves. Yes is how a reader says they did not mean to go, and it
  /// hands them back the form with their edits on it and the save button
  /// where it always was.
  Future<void> _leave() async {
    if (!_hasUnsavedEdits) {
      if (mounted) context.pop();
      return;
    }

    final bool? save = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        key: const ValueKey<String>('profileEdit.unsavedDialog'),
        backgroundColor: Colors.white,
        title: Text(
          'profileEdit.saveChangesTitle'.tr(),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
        ),
        actions: <Widget>[
          TextButton(
            key: const ValueKey<String>('profileEdit.unsavedNo'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('common.no'.tr()),
          ),
          FilledButton(
            key: const ValueKey<String>('profileEdit.unsavedYes'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: MerzoxColors.kColorEE6C4D,
            ),
            child: Text('common.yes'.tr()),
          ),
        ],
      ),
    );

    if (!mounted) return;

    // Yes leaves the form standing with the edits still on it, so the reader
    // saves it themselves with the button at the foot of the page. It does
    // not save on their behalf: a save is a request that can fail, and one
    // made from a dialog that has already closed would report its failure to
    // somebody who thought they had finished.
    //
    // Dismissing the dialog - a tap outside, or the system back - is neither
    // answer, and does the same thing for the same reason: nothing. It is not
    // carried down the page though: that would be the screen acting on an
    // answer nobody gave.
    if (save == null) return;

    if (save) {
      _showSaveButton();
      return;
    }

    context.pop();
  }

  /// Brings the save button into view.
  ///
  /// Yes means "I did not mean to leave", and the thing to do next is press
  /// save - which may be a screen below where the reader is standing. Without
  /// this the form comes back looking exactly as it did, and being told to
  /// press a button one cannot see is not being told anything.
  void _showSaveButton() {
    if (!_formScroll.hasClients) return;

    _formScroll.animateTo(
      _formScroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  void _submit() {
    final isFormValid = _formKey.currentState?.validate() ?? false;

    final chosen = [
      _birthYear,
      _birthMonth,
      _birthDay,
    ].where((part) => part != null).length;

    String? birthDateError;
    String? birthDate;

    if (chosen > 0 && chosen < 3) {
      // The birth date stays optional, but a half-filled one is a mistake
      // rather than an intent to clear it.
      birthDateError = 'profileEdit.birthDateIncomplete'.tr();
    } else if (chosen == 3) {
      birthDate = _selectedBirthDate();

      if (birthDate == null) {
        birthDateError = 'profileEdit.birthDateInvalid'.tr();
      }
    }

    if (_birthDateError != birthDateError) {
      setState(() => _birthDateError = birthDateError);
    }

    if (!isFormValid || birthDateError != null) {
      return;
    }

    final user = context.read<ProfileEditBloc>().state.user;
    context.read<ProfileEditBloc>().add(
      ProfileEditSubmitted(
        name: _canChangeName && _nameController.text.trim() != user?.name
            ? _nameController.text.trim()
            : null,
        gender: _canChangeGender && _gender != user?.gender ? _gender : null,
        // An unchanged date is not resent: the PATCH carries the field only
        // when it actually differs from the stored value.
        birthDate: birthDate == _initialBirthDate ? null : birthDate,
        emails: _emails
            .map(
              (email) => ContactEmail(
                value: email.controller.text.trim().toLowerCase(),
                label: email.label,
              ),
            )
            .where((email) => email.value.isNotEmpty)
            .toList(),
        phones: _phones
            .map(
              (phone) => ContactPhone(
                value: _normalizePhone(phone.controller.text),
                label: phone.label,
              ),
            )
            .where((phone) => phone.value.isNotEmpty)
            .toList(),
      ),
    );
  }

  String _normalizePhone(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('+')) {
      final digits = trimmed.replaceAll(RegExp(r'\D'), '');
      return digits.isEmpty ? '' : '+$digits';
    }
    final digits = trimmed.replaceAll(RegExp(r'\D'), '');
    final withoutLeadingZero = digits.startsWith('0')
        ? digits.substring(1)
        : digits;
    return withoutLeadingZero.isEmpty ? '' : '+970$withoutLeadingZero';
  }

  void _addEmail() {
    setState(() => _emails.add(_EmailFieldData(label: 'other')));
  }

  void _addPhone() {
    setState(() => _phones.add(_PhoneFieldData(label: 'other')));
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ProfileEditBloc, ProfileEditState>(
      listener: (context, state) {
        if (state.status == ProfileEditStatus.success) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('profileEdit.saved'.tr())));

          // Saving used to walk to the customer home, which for a shopkeeper
          // editing their own details meant the app appeared to change sides
          // under them. Saving is not leaving: the screen says it saved and
          // stays, and the reader closes it by the way they came.
          final user = state.user;
          if (user != null) {
            setState(() => _adopt(user));
          }
        }

        if (state.status == ProfileEditStatus.failure &&
            state.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(localizeApiErrorOrRaw(state.errorMessage!))),
          );
        }
      },
      builder: (context, state) {
        final user = state.user;
        if (user != null) {
          _initialize(user);
        }

        final isBusy =
            state.status == ProfileEditStatus.loading ||
            state.status == ProfileEditStatus.saving;

        return Directionality(
          textDirection: Directionality.of(context),
          child: Scaffold(
            backgroundColor: Colors.white,
            body: SafeArea(
              child: state.status == ProfileEditStatus.loading && user == null
                  ? const Center(child: CircularProgressIndicator())
                  : Form(
                      key: _formKey,
                      child: ListView(
                        controller: _formScroll,
                        padding: const EdgeInsets.fromLTRB(21, 18, 21, 32),
                        children: [
                          ProfileEditHeader(onBack: _leave),
                          const SizedBox(height: 34),
                          _ProfileLabel(text: 'auth.fullNameLabel'.tr()),
                          _ProfileTextField(
                            controller: _nameController,
                            hintText: 'auth.fullNameHint'.tr(),
                            enabled: _canChangeName && !isBusy,
                            validator: (value) {
                              if (!_canChangeName) return null;
                              return (value?.trim().length ?? 0) >= 2
                                  ? null
                                  : 'profileEdit.nameTooShort'.tr();
                            },
                          ),
                          if (!_canChangeName)
                            _RestrictionText(
                              text: 'profileEdit.nameChangeUsed'.tr(),
                            ),
                          const SizedBox(height: 18),
                          _ProfileLabel(
                            text: 'businessEnrollment.emailLabel'.tr(),
                          ),
                          ..._emails.asMap().entries.map(
                            (entry) => _EmailInputRow(
                              data: entry.value,
                              enabled: !isBusy,
                              canRemove: _emails.length > 1,
                              onRemove: () {
                                setState(() {
                                  entry.value.dispose();
                                  _emails.removeAt(entry.key);
                                });
                              },
                            ),
                          ),
                          _AddLineButton(
                            text: 'profileEdit.addEmail'.tr(),
                            onTap: _addEmail,
                          ),
                          const SizedBox(height: 18),
                          _ProfileLabel(
                            text: 'businessEnrollment.phoneLabel'.tr(),
                          ),
                          ..._phones.asMap().entries.map(
                            (entry) => _PhoneInputRow(
                              data: entry.value,
                              enabled: !isBusy,
                              canRemove: _phones.length > 1,
                              onRemove: () {
                                setState(() {
                                  entry.value.dispose();
                                  _phones.removeAt(entry.key);
                                });
                              },
                            ),
                          ),
                          _AddLineButton(
                            text: 'profileEdit.addPhone'.tr(),
                            onTap: _addPhone,
                          ),
                          const SizedBox(height: 18),
                          _ProfileLabel(text: 'profileEdit.addresses'.tr()),
                          ..._addresses.map(
                            (entry) => _AddressLineRow(
                              line: entry.line,
                              enabled: !isBusy && !_addressesBusy,
                              onRemove: () => _removeAddress(entry),
                            ),
                          ),
                          _AddLineButton(
                            text: 'profileEdit.addAddress'.tr(),
                            onTap: _addAddress,
                          ),
                          const SizedBox(height: 18),
                          _ProfileLabel(text: 'profileEdit.gender'.tr()),
                          Row(
                            // Under the word they answer. They sat at the
                            // far edge, across the screen from `الجنس`.
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              _GenderChoice(
                                label: 'profileEdit.genderFemale'.tr(),
                                value: 'female',
                                groupValue: _gender,
                                enabled: _canChangeGender && !isBusy,
                                onChanged: (value) {
                                  setState(() => _gender = value);
                                },
                              ),
                              const SizedBox(width: 28),
                              _GenderChoice(
                                label: 'profileEdit.genderMale'.tr(),
                                value: 'male',
                                groupValue: _gender,
                                enabled: _canChangeGender && !isBusy,
                                onChanged: (value) {
                                  setState(() => _gender = value);
                                },
                              ),
                            ],
                          ),
                          if (!_canChangeGender)
                            _RestrictionText(
                              text: 'profileEdit.genderChangeUsed'.tr(),
                            ),
                          const SizedBox(height: 20),
                          _ProfileLabel(text: 'profileEdit.birthDate'.tr()),
                          _BirthDateSelectors(
                            day: _birthDay,
                            month: _birthMonth,
                            year: _birthYear,
                            maxDay: _maxBirthDay,
                            maxMonth: _maxBirthMonth,
                            latestYear: _today.year,
                            earliestYear: _earliestGregorianYear,
                            enabled: !isBusy,
                            errorText: _birthDateError,
                            onDayChanged: _onBirthDayChanged,
                            onMonthChanged: _onBirthMonthChanged,
                            onYearChanged: _onBirthYearChanged,
                          ),
                          const SizedBox(height: kProfileSaveGap),
                          Center(
                            child: SizedBox(
                              width: 210,
                              height: 55,
                              child: FilledButton(
                                onPressed: isBusy ? null : _submit,
                                style: FilledButton.styleFrom(
                                  backgroundColor: MerzoxColors.kColorEE6C4D,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                                child: isBusy
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(
                                        'common.save'.tr(),
                                        style: const TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                              ),
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
}

/// The run of white between the birth date and the Save button.
///
/// It was 124, which put the button so far below the last field that the two
/// stopped reading as one form. Half of that still separates the button from
/// the fields without stranding it.
const double kProfileSaveGap = 62;

/// Where the language toggle stands, measured in from the trailing edge.
///
/// Between two things, and centred between them. The bell that floats over
/// this corner is a white disc on a white bar, so what the eye sees of it is
/// the glyph, which ends 40 in from the edge - eight for the bell's inset,
/// eight for its own padding, twenty-four for the icon. The title begins at
/// 94. The globe is put in the middle of that span.
///
/// Standing it hard against the 48 the bell reserves left it a third of the
/// way across instead, near enough to the words to read as part of them.
const double kProfileToggleInset = 43;

/// How much of each end of the bar the title must keep clear.
///
/// The toggle now stands past the bell - eight for the bell's inset from the
/// edge, forty for the bell, forty for the toggle itself - and four more keeps
/// the words off the globe. The same room is left at the other end so the
/// title stays centred on the screen rather than on what is left of it.
///
/// It matters at the reader's own settings: at a system font scale of 1.3 the
/// title is 243 wide, which without this runs straight through the globe.
const double kProfileHeaderTitleRoom = 92;

/// The bar over the form: the way back, the title, and the language toggle.
///
/// Public so its geometry can be measured. Two of the three things in it are
/// placed against something outside the bar - the reading direction, and the
/// bell that floats above every screen - and neither can be checked by
/// reading the bar's own code.
class ProfileEditHeader extends StatelessWidget {
  final VoidCallback onBack;

  const ProfileEditHeader({super.key, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: kProfileHeaderTitleRoom,
              ),
              // Shrinks only when it has to. At the ordinary font scale the
              // title is drawn at its full size and nothing here touches it.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'profileEdit.title'.tr(),
                  maxLines: 1,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2B2B2B),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: IconButton(
              tooltip: 'common.back'.tr(),
              onPressed: onBack,
              // Named for what it does, not for where it points. This icon
              // carries `matchTextDirection`, so Material turns it round in a
              // right-to-left reading on its own; picking the forward arrow
              // there turned it round a second time and left Arabic with the
              // English arrow.
              icon: const Icon(
                Icons.arrow_back_ios_new_rounded,
                size: 28,
                color: Color(0xFF686868),
              ),
            ),
          ),
          // The bell floats over every screen at this corner and covered the
          // globe almost exactly. It now stands clear of the bell, midway
          // between it and the title.
          const Align(
            alignment: AlignmentDirectional.centerEnd,
            child: Padding(
              padding: EdgeInsetsDirectional.only(end: kProfileToggleInset),
              child: LanguageToggleButton(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileLabel extends StatelessWidget {
  final String text;

  const _ProfileLabel({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        textAlign: TextAlign.start,
        style: const TextStyle(fontSize: 14, color: Color(0xFF2B2B2B)),
      ),
    );
  }
}

class _ProfileTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final bool enabled;
  final String? Function(String?)? validator;

  const _ProfileTextField({
    required this.controller,
    required this.hintText,
    this.enabled = true,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        textAlign: TextAlign.start,
        validator: validator,
        decoration: _profileInputDecoration(hintText),
      ),
    );
  }
}

class _EmailInputRow extends StatelessWidget {
  final _EmailFieldData data;
  final bool enabled;
  final bool canRemove;
  final VoidCallback onRemove;

  const _EmailInputRow({
    required this.data,
    required this.enabled,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return _LabeledContactRow(
      controller: data.controller,
      label: data.label,
      labels: profileEmailLabels,
      hintText: 'profileEdit.emailHint'.tr(),
      enabled: enabled,
      canRemove: canRemove,
      keyboardType: TextInputType.emailAddress,
      onLabelChanged: (value) => data.label = value,
      onRemove: onRemove,
      validator: (value) {
        final trimmed = value?.trim() ?? '';
        if (trimmed.isEmpty) return null;
        return RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(trimmed)
            ? null
            : 'validation.invalidEmail'.tr();
      },
    );
  }
}

class _PhoneInputRow extends StatelessWidget {
  final _PhoneFieldData data;
  final bool enabled;
  final bool canRemove;
  final VoidCallback onRemove;

  const _PhoneInputRow({
    required this.data,
    required this.enabled,
    required this.canRemove,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return _LabeledContactRow(
      controller: data.controller,
      label: data.label,
      labels: profilePhoneLabels,
      hintText: 'profileEdit.phoneHint'.tr(),
      enabled: enabled,
      canRemove: canRemove,
      keyboardType: TextInputType.phone,
      onLabelChanged: (value) => data.label = value,
      onRemove: onRemove,
      validator: (value) {
        final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
        if (digits.isEmpty) return null;
        return digits.length >= 7 ? null : 'profileEdit.phoneTooShort'.tr();
      },
    );
  }
}

class _LabeledContactRow extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final Map<String, String> labels;
  final String hintText;
  final bool enabled;
  final bool canRemove;
  final TextInputType keyboardType;
  final ValueChanged<String> onLabelChanged;
  final VoidCallback onRemove;
  final String? Function(String?)? validator;

  const _LabeledContactRow({
    required this.controller,
    required this.label,
    required this.labels,
    required this.hintText,
    required this.enabled,
    required this.canRemove,
    required this.keyboardType,
    required this.onLabelChanged,
    required this.onRemove,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            height: 54,
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: labels.containsKey(label)
                  ? label
                  : labels.keys.first,
              items: labels.entries
                  .map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(
                        entry.value.tr(),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: enabled
                  ? (value) {
                      if (value != null) onLabelChanged(value);
                    }
                  : null,
              decoration: _profileInputDecoration(''),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 54,
              child: TextFormField(
                controller: controller,
                enabled: enabled,
                keyboardType: keyboardType,
                textAlign: TextAlign.start,
                validator: validator,
                decoration: _profileInputDecoration(hintText),
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: canRemove
                ? IconButton(
                    tooltip: 'common.delete'.tr(),
                    onPressed: enabled ? onRemove : null,
                    // A bin, not a red minus in a circle. The minus read as
                    // a subtraction from a number rather than as removing the
                    // line it sits beside.
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: MerzoxColors.kColorE40909,
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

/// One saved address, in the shape the email and phone rows have.
///
/// It shows the line rather than the six fields behind it: a saved address is
/// read here, not edited here, and the form that made it is where it is
/// changed.
class _AddressLineRow extends StatelessWidget {
  final String line;
  final bool enabled;
  final VoidCallback onRemove;

  const _AddressLineRow({
    required this.line,
    required this.enabled,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              alignment: AlignmentDirectional.centerStart,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: MerzoxColors.kColorB9DDF3),
              ),
              child: Text(
                line,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  color: MerzoxColors.kColor2B2B2B,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: IconButton(
              tooltip: 'common.delete'.tr(),
              onPressed: enabled ? onRemove : null,
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: MerzoxColors.kColorE40909,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddLineButton extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _AddLineButton({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: TextButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(text),
        style: TextButton.styleFrom(foregroundColor: MerzoxColors.kColor3D5A80),
      ),
    );
  }
}

class _GenderChoice extends StatelessWidget {
  final String label;
  final String value;
  final String groupValue;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _GenderChoice({
    required this.label,
    required this.value,
    required this.groupValue,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;

    return InkWell(
      onTap: enabled ? () => onChanged(value) : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 18,
            height: 18,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? MerzoxColors.kColor98C1D9
                    : MerzoxColors.kColor8D99AE,
                width: 2,
              ),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? MerzoxColors.kColor98C1D9
                    : Colors.transparent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Keys for the three XD birth-date controls.
///
/// Selection is real state on the page, so a test asserts against the control
/// rather than against a rendered placeholder string.
const birthDayFieldKey = Key('profileEdit.birthDay');
const birthMonthFieldKey = Key('profileEdit.birthMonth');
const birthYearFieldKey = Key('profileEdit.birthYear');

/// The XD Day | Month | Year row, made interactive.
///
/// The visual structure is unchanged: three horizontal bordered dropdown-style
/// controls sharing the profile form's border, radius and placeholder colours,
/// laid out directionally so RTL and LTR both read Day first.
class _BirthDateSelectors extends StatelessWidget {
  final int? day;
  final int? month;
  final int? year;
  final int maxDay;
  final int maxMonth;
  final int latestYear;
  final int earliestYear;
  final bool enabled;
  final String? errorText;
  final ValueChanged<int?> onDayChanged;
  final ValueChanged<int?> onMonthChanged;
  final ValueChanged<int?> onYearChanged;

  const _BirthDateSelectors({
    required this.day,
    required this.month,
    required this.year,
    required this.maxDay,
    required this.maxMonth,
    required this.latestYear,
    required this.earliestYear,
    required this.enabled,
    required this.errorText,
    required this.onDayChanged,
    required this.onMonthChanged,
    required this.onYearChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _BirthDateDropdown(
                fieldKey: birthDayFieldKey,
                label: 'profileEdit.day'.tr(),
                value: day,
                options: [
                  for (var option = 1; option <= maxDay; option++) option,
                ],
                enabled: enabled,
                onChanged: onDayChanged,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _BirthDateDropdown(
                fieldKey: birthMonthFieldKey,
                label: 'profileEdit.month'.tr(),
                value: month,
                options: [
                  for (var option = 1; option <= maxMonth; option++) option,
                ],
                enabled: enabled,
                onChanged: onMonthChanged,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _BirthDateDropdown(
                fieldKey: birthYearFieldKey,
                label: 'profileEdit.year'.tr(),
                value: year,
                // The whole past calendar domain, newest first. The list is
                // long on purpose: truncating it to a span of years would be a
                // maximum-age rule, and this product has none.
                options: [
                  for (
                    var option = latestYear;
                    option >= earliestYear;
                    option--
                  )
                    option,
                ],
                enabled: enabled,
                onChanged: onYearChanged,
              ),
            ),
          ],
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              errorText!,
              style: TextStyle(fontSize: 12, color: MerzoxColors.kColorE40909),
            ),
          ),
      ],
    );
  }
}

class _BirthDateDropdown extends StatelessWidget {
  final Key fieldKey;
  final String label;
  final int? value;
  final List<int> options;
  final bool enabled;
  final ValueChanged<int?> onChanged;

  const _BirthDateDropdown({
    required this.fieldKey,
    required this.label,
    required this.value,
    required this.options,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // The unselected label keeps the XD placeholder colour, and is repeated as
    // the disabled hint so a busy form still reads Day / Month / Year.
    final placeholder = Text(
      label,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 14, color: MerzoxColors.kColorC7C7C7),
    );

    return SizedBox(
      height: 55,
      child: InputDecorator(
        decoration: _profileInputDecoration(''),
        child: DropdownButtonHideUnderline(
          // A plain DropdownButton is used rather than the form-field variant
          // because the page owns the value: when a month change invalidates
          // the chosen day, the control must follow that state immediately.
          child: DropdownButton<int>(
            key: fieldKey,
            isExpanded: true,
            isDense: true,
            menuMaxHeight: 320,
            value: options.contains(value) ? value : null,
            hint: placeholder,
            disabledHint: placeholder,
            icon: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: MerzoxColors.kColor3D5A80,
            ),
            borderRadius: BorderRadius.circular(4),
            items: [
              for (final option in options)
                DropdownMenuItem<int>(
                  value: option,
                  child: Text('$option', style: const TextStyle(fontSize: 14)),
                ),
            ],
            onChanged: enabled ? onChanged : null,
          ),
        ),
      ),
    );
  }
}

/// The length of a Gregorian month: day zero of the next month is its last.
int _daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

class _RestrictionText extends StatelessWidget {
  final String text;

  const _RestrictionText({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: MerzoxColors.kColor8D99AE),
      ),
    );
  }
}

InputDecoration _profileInputDecoration(String hintText) {
  return InputDecoration(
    hintText: hintText,
    hintStyle: TextStyle(fontSize: 14, color: MerzoxColors.kColorC7C7C7),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: _profileBorder(MerzoxColors.kColorB9DDF3),
    enabledBorder: _profileBorder(MerzoxColors.kColorB9DDF3),
    focusedBorder: _profileBorder(MerzoxColors.kColor98C1D9, 1.4),
    errorBorder: _profileBorder(MerzoxColors.kColorE40909),
    focusedErrorBorder: _profileBorder(MerzoxColors.kColorE40909, 1.4),
  );
}

OutlineInputBorder _profileBorder(Color color, [double width = 1]) {
  return OutlineInputBorder(
    borderRadius: BorderRadius.circular(4),
    borderSide: BorderSide(color: color, width: width),
  );
}

class _EmailFieldData {
  final TextEditingController controller;
  String label;

  _EmailFieldData({String value = '', this.label = 'personal'})
    : controller = TextEditingController(text: value);

  void dispose() => controller.dispose();
}

class _PhoneFieldData {
  final TextEditingController controller;
  String label;

  _PhoneFieldData({String value = '', this.label = 'mobile'})
    : controller = TextEditingController(text: value);

  void dispose() => controller.dispose();
}

/// What a saved address may be called, and the words for each.
///
/// The keys are the wire values, and the server keeps only these: anything
/// else it is sent is silently rewritten to `other`, so a label added here
/// alone would look accepted and come back changed. A test holds the two
/// lists together.
const profileEmailLabels = {
  'personal': 'profileEdit.contactLabels.personal',
  'work': 'profileEdit.contactLabels.work',
  'home': 'profileEdit.contactLabels.home',
  'other': 'profileEdit.contactLabels.other',
};

const profilePhoneLabels = {
  'mobile': 'profileEdit.contactLabels.mobile',
  'work': 'profileEdit.contactLabels.work',
  'home': 'profileEdit.contactLabels.home',
  'fax': 'profileEdit.contactLabels.fax',
  'other': 'profileEdit.contactLabels.other',
};
