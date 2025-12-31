/// A helper class to store and manage user-selected filtering parameters.
class FilterCriteria {
  String? city;
  String? cuisine;
  String? reviewer;
  List<String> selectedTags = [];

  /// Returns true if no filters are currently applied.
  bool get isEmpty => city == null && cuisine == null && reviewer == null && selectedTags.isEmpty;
}