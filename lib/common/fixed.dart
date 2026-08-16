import 'iterable.dart';

class FixedList<T> {
  final int maxLength;
  final List<T> _list;

  // Which generation of the shared buffer this wrapper names. Logs and requests
  // arrive faster than they are rendered, and copying a 500-entry buffer per
  // arrival just to produce a new identity was the dominant cost on that path,
  // so `append` hands out a new generation over the same buffer instead.
  final int _revision;
  List<T>? _snapshot;

  FixedList(this.maxLength, {List<T>? list})
    : _list = (list ?? [])..truncate(maxLength),
      _revision = 0;

  FixedList._(this.maxLength, this._list, this._revision);

  int get revision => _revision;

  // In-place edits, for a buffer the caller owns outright. State that is
  // published through a provider uses `append` instead, so that listeners see
  // the generation change.
  void add(T item) {
    _list.add(item);
    _list.truncate(maxLength);
    _snapshot = null;
  }

  void clear() {
    _list.clear();
    _snapshot = null;
  }

  // Shares the buffer rather than copying it, so appending is O(1). Safe
  // because `list` snapshots eagerly: whoever holds the previous generation
  // already took their copy before this append could run.
  FixedList<T> append(T item) {
    add(item);
    return FixedList._(maxLength, _list, _revision + 1);
  }

  // An immutable copy, cached until the next mutation so that several listeners
  // reading the same generation share one allocation.
  List<T> get list => _snapshot ??= List.unmodifiable(_list);

  int get length => _list.length;

  T operator [](int index) => _list[index];

  FixedList<T> copyWith() {
    return FixedList(maxLength, list: List.of(_list));
  }

  @override
  bool operator ==(Object other) =>
      other is FixedList<T> &&
      identical(other._list, _list) &&
      other._revision == _revision;

  @override
  int get hashCode => Object.hash(identityHashCode(_list), _revision);
}
