import 'package:flutter/services.dart';

/// Which keyboard a field asks for.
///
/// A field that names none gets the letters, which is right for a name and
/// wrong for a price - and the wrongness is invisible in a screenshot. It
/// shows up only when somebody types, as an extra press to reach the digits
/// every single time.
///
/// Named rather than written out at each field for two reasons. The first is
/// that `TextInputType.number` and `TextInputType.numberWithOptions(decimal:
/// true)` look alike and are not: the plain one offers no decimal separator,
/// so a merchant cannot type 12.50 into it on iOS. The second is that a rule
/// spelled out thirty times is a rule that holds in twenty-nine places.

/// A telephone number. Carries `+`, `*` and `#` as well as the digits, which a
/// plain number pad does not - and an international number begins with one of
/// them.
const TextInputType kMerzoxPhoneKeyboard = TextInputType.phone;

/// An email address: the pad with `@` and `.com` on it.
const TextInputType kMerzoxEmailKeyboard = TextInputType.emailAddress;

/// A count of things - a quantity, a stock level. Whole numbers only, because
/// half an item is not a thing that can be in stock.
const TextInputType kMerzoxWholeNumberKeyboard = TextInputType.number;

/// An amount of money. Digits and a decimal separator.
///
/// Prices are parsed as `double` throughout, so a field that cannot type a
/// decimal point is a field that cannot express half the prices in a shop.
const TextInputType kMerzoxMoneyKeyboard = TextInputType.numberWithOptions(
  decimal: true,
);
