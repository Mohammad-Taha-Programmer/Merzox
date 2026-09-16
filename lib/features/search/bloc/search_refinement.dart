/// Where in a name the words the customer typed have to sit.
///
/// The search used to have one answer - somewhere in there - which is right
/// until two shops share a name. `أبو خالد للألبان` and `حلويات أبو خالد` are
/// both "أبو خالد", and a customer who means one of them has no way to say so.
enum SearchMatch {
  /// The name begins with the words.
  starts,

  /// The words appear anywhere in it. What the single box always meant.
  contains,

  /// The name ends with the words.
  ends,

  /// Goods only: any of the words, from the start of a word.
  ///
  /// Merchants name the same thing differently - `جاكيت`, `جاكيتات شتوية`,
  /// `جاكيت جلد رجالي` - so asking for the phrase finds one shop and misses
  /// three. This asks for the words instead, which is what "sells something
  /// like this" means when nobody agreed on a catalogue.
  similar;

  /// What the server calls it.
  String get wire => name;

  /// The ones a shop name is offered. `similar` is not among them: it would
  /// quietly widen `أبو خالد` into every shop with `أبو` or `خالد` in it, and
  /// a name is a name.
  static const List<SearchMatch> forShops = <SearchMatch>[
    SearchMatch.starts,
    SearchMatch.contains,
    SearchMatch.ends,
  ];

  static const List<SearchMatch> forProducts = SearchMatch.values;
}

/// The whole of what the search is being asked, beyond the words themselves.
class SearchRefinement {
  final SearchMatch match;
  final String product;
  final SearchMatch productMatch;

  const SearchRefinement({
    this.match = SearchMatch.contains,
    this.product = '',
    this.productMatch = SearchMatch.contains,
  });

  bool get hasProduct => product.trim().isNotEmpty;

  /// Whether anything here narrows the search beyond the plain one box.
  ///
  /// Used to decide whether a saved search is the same search, and to tell a
  /// reader that a refinement is in force when the results look thin.
  bool get isPlain => match == SearchMatch.contains && !hasProduct;

  SearchRefinement copyWith({
    SearchMatch? match,
    String? product,
    SearchMatch? productMatch,
  }) {
    return SearchRefinement(
      match: match ?? this.match,
      product: product ?? this.product,
      productMatch: productMatch ?? this.productMatch,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SearchRefinement &&
      other.match == match &&
      other.product.trim() == product.trim() &&
      other.productMatch == productMatch;

  @override
  int get hashCode => Object.hash(match, product.trim(), productMatch);
}
