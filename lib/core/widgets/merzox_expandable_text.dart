import 'package:flutter/material.dart';

/// Text that is cut short until somebody asks for the rest of it.
///
/// A product called `طقم أواني طهي ستانلس ستيل مقاوم للخدش 12 قطعة` gets one
/// line beside its price, and the line ends in an ellipsis. That is the right
/// answer for a page that has to stay readable and the wrong answer for a
/// customer deciding which of two similar things they are looking at. So the
/// cut is not final: a press shows the whole of it, and a second press puts it
/// back.
///
/// It lays out exactly as the `Text` it replaces. That is the reason the
/// measuring happens on the press rather than in a `LayoutBuilder`: a builder
/// takes all the width it is offered, and this line usually sits in a row
/// beside a price that the line is not entitled to push around.
///
/// It does not open a dialog either. The reader is looking at this line, in
/// this place, beside the things it belongs with; lifting it into a box over
/// the screen loses all of that to show the same words.
class MerzoxExpandableText extends StatefulWidget {
  final String text;

  /// How many lines it gets before it is cut.
  final int maxLines;

  final TextStyle? style;
  final TextAlign? textAlign;

  /// Named so a test can press exactly this one.
  final Key? valueKey;

  /// What a press does when there is nothing to reveal.
  ///
  /// The seller's name is the way into their shop and is also the line most
  /// likely to be cut. When it fits, a press goes to the shop as it always
  /// did; when it does not, a press reads the name and the shop stays one
  /// press away on the logo beside it. A press that was asked to reveal
  /// something should not also walk off the page.
  final VoidCallback? onTapWhenWhole;

  const MerzoxExpandableText({
    super.key,
    required this.text,
    this.maxLines = 1,
    this.style,
    this.textAlign,
    this.valueKey,
    this.onTapWhenWhole,
  });

  @override
  State<MerzoxExpandableText> createState() => _MerzoxExpandableTextState();
}

class _MerzoxExpandableTextState extends State<MerzoxExpandableText> {
  bool _whole = false;

  @override
  void didUpdateWidget(MerzoxExpandableText oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Different words are a different question. A line that was opened stays
    // open; a line that was replaced starts cut again.
    if (oldWidget.text != widget.text) _whole = false;
  }

  /// Whether these words, in this style, at the width this line was given,
  /// need more lines than they are allowed.
  ///
  /// The rendered width rather than a guess from the string's length: the same
  /// name fits on one phone and not on another, and an Arabic name and an
  /// English one of equal length are not equally wide.
  bool _isCut() {
    final RenderObject? box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;

    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: widget.style ?? DefaultTextStyle.of(context).style,
      ),
      maxLines: widget.maxLines,
      textAlign: widget.textAlign ?? TextAlign.start,
      textDirection: Directionality.of(context),
    )..layout(maxWidth: box.size.width);

    final bool exceeded = painter.didExceedMaxLines;
    painter.dispose();

    return exceeded;
  }

  void _onTap() {
    if (_whole || _isCut()) {
      setState(() => _whole = !_whole);
      return;
    }

    widget.onTapWhenWhole?.call();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: Text(
        widget.text,
        key: widget.valueKey,
        maxLines: _whole ? null : widget.maxLines,
        overflow: _whole ? TextOverflow.clip : TextOverflow.ellipsis,
        textAlign: widget.textAlign,
        style: widget.style,
      ),
    );
  }
}
