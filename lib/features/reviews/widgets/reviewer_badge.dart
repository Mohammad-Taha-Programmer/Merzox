import 'package:flutter/material.dart';
import 'package:merzox/core/constants/colors.dart';
import 'package:merzox/core/widgets/merzox_icons.dart';
import 'package:merzox/core/widgets/remote_circle_avatar.dart';
import 'package:merzox/features/authentication/account_avatar.dart';
import 'package:merzox/features/authentication/bloc/auth_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Who said it: a picture and a name, side by side.
///
/// A review used to be a rating and a paragraph with a blank blue disc beside
/// it. The disc was never filled in - the review carries the name it was
/// written under and nothing else - so every reviewer on a product looked like
/// the same anonymous person, and the reader had no way to tell one of them
/// from the next except by the words.
///
/// The same pair says who is about to write, above the box they write in, so
/// a reader can see which account they are reviewing as before they publish
/// under it. One widget for both, because they are the same claim.
class ReviewerBadge extends StatelessWidget {
  final String name;

  /// Empty where the account has no picture, which draws the figure instead.
  final String avatarUrl;

  final double radius;
  final TextStyle? nameStyle;

  /// Named so a test can find exactly this one.
  final Key? nameKey;

  const ReviewerBadge({
    required this.name,
    required this.avatarUrl,
    this.radius = 18,
    this.nameStyle,
    this.nameKey,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        RemoteCircleAvatar(
          url: avatarUrl,
          radius: radius,
          backgroundColor: MerzoxColors.kColorDEEEF8,
          fallback: Icon(
            MerzoxIcons.homeScreenProfile,
            size: radius * 1.2 * MerzoxIcons.accountFigureSizeFactor,
            color: MerzoxColors.kColor3D5A80,
          ),
        ),
        const SizedBox(width: 9),
        Flexible(
          child: Text(
            name,
            key: nameKey,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style:
                nameStyle ??
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// The reader's own picture and name.
///
/// The name is read once from storage: it is written there when the session
/// is made and changed only by the profile screen, so a rebuild of this row
/// has nothing new to learn. The picture is watched rather than read, because
/// it does change while the app is running - the profile tab uploads one and
/// every place that draws the account has to hear about it, which is what
/// [AccountAvatar] exists for.
///
/// A guest has no name to draw and gets nothing at all, rather than a figure
/// beside the word for an unnamed account: the row is there to say which
/// account this is, and for a guest there is no answer to that yet.
class CurrentAccountBadge extends StatefulWidget {
  final double radius;
  final TextStyle? nameStyle;
  final Key? nameKey;

  const CurrentAccountBadge({
    this.radius = 18,
    this.nameStyle,
    this.nameKey,
    super.key,
  });

  @override
  State<CurrentAccountBadge> createState() => _CurrentAccountBadgeState();
}

class _CurrentAccountBadgeState extends State<CurrentAccountBadge> {
  late final Future<String> _name;

  @override
  void initState() {
    super.initState();
    _name = _storedName();
  }

  static Future<String> _storedName() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();

    return prefs.getString(AuthBloc.nameKey)?.trim() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _name,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        final String name = snapshot.data ?? '';
        if (name.isEmpty) return const SizedBox.shrink();

        return ValueListenableBuilder<String>(
          valueListenable: AccountAvatar.url,
          builder: (BuildContext context, String url, Widget? _) {
            return ReviewerBadge(
              name: name,
              avatarUrl: url,
              radius: widget.radius,
              nameStyle: widget.nameStyle,
              nameKey: widget.nameKey,
            );
          },
        );
      },
    );
  }
}
