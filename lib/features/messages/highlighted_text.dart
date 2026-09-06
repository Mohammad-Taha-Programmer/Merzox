import 'package:flutter/material.dart';

/// Where a searched-for phrase actually sits inside a line of text.
///
/// Returned as plain index pairs rather than as spans so the arithmetic can be
/// stated in a test without a widget tree: the highlight is the one part of
/// search that is easy to get subtly wrong and impossible to see in a
/// screenshot when it is off by a character.
List<({int start, int end})> highlightRanges(String text, String query) {
  final String needle = query.trim();
  if (needle.isEmpty || text.isEmpty) return const [];

  final String haystack = text.toLowerCase();
  final String lowered = needle.toLowerCase();
  final List<({int start, int end})> found = <({int start, int end})>[];

  int at = haystack.indexOf(lowered);
  while (at != -1) {
    found.add((start: at, end: at + lowered.length));
    // Continues past the whole match, so "aa" in "aaaa" is two hits and not
    // three overlapping ones.
    at = haystack.indexOf(lowered, at + lowered.length);
  }

  return found;
}

/// Draws [text] with every occurrence of [query] marked.
///
/// The marked runs keep the surrounding style and change only what a reader
/// needs to see to find their word again: weight and a wash behind it.
TextSpan highlightedSpan({
  required String text,
  required String query,
  required TextStyle style,
  required Color background,
  Color? foreground,
}) {
  final List<({int start, int end})> ranges = highlightRanges(text, query);

  if (ranges.isEmpty) {
    return TextSpan(text: text, style: style);
  }

  final List<TextSpan> parts = <TextSpan>[];
  int cursor = 0;

  for (final ({int start, int end}) range in ranges) {
    if (range.start > cursor) {
      parts.add(
        TextSpan(text: text.substring(cursor, range.start), style: style),
      );
    }

    parts.add(
      TextSpan(
        text: text.substring(range.start, range.end),
        style: style.copyWith(
          fontWeight: FontWeight.w800,
          backgroundColor: background,
          color: foreground ?? style.color,
        ),
      ),
    );

    cursor = range.end;
  }

  if (cursor < text.length) {
    parts.add(TextSpan(text: text.substring(cursor), style: style));
  }

  return TextSpan(children: parts);
}
