import 'dart:async';

import 'package:collection/collection.dart';
import 'package:drift/drift.dart';
import 'package:fl_clash/common/common.dart';
import 'package:fl_clash/database/database.dart';
import 'package:fl_clash/models/models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'generated/database.g.dart';

Future<void> withRollback<T>({
  required T snapshot,
  required FutureOr<void> Function() action,
  required void Function(T snapshot) rollback,
}) async {
  try {
    await action();
  } catch (e, s) {
    rollback(snapshot);
    Error.throwWithStackTrace(e, s);
  }
}

/// Applies [next] through [write] and persists it with [action], restoring
/// [previous] if the write fails.
Future<void> _persistOptimistically<T>(
  T previous,
  T next,
  void Function(T value) write,
  FutureOr<void> Function() action,
) {
  write(next);
  return withRollback(snapshot: previous, action: action, rollback: write);
}

/// Optimistic writes for the async notifiers below.
///
/// Every mutation lands in the in-memory value first and reaches the database
/// afterwards, so the UI never waits on SQLite. A failed write restores the
/// value the notifier held before the mutation.
mixin OptimisticMixin<T> on AsyncNotifierMixin<T> {
  /// Applies [next] and persists it without awaiting.
  ///
  /// Callers are UI event handlers and [next] is already on screen, so there is
  /// nothing to hand a failure to: the value rolls back and the error surfaces
  /// through the zone handler installed in `main()`.
  void optimistic(T next, FutureOr<void> Function() action) {
    unawaited(optimisticAsync(next, action));
  }

  /// [optimistic] with the write handed back, for callers that can report it.
  Future<void> optimisticAsync(T next, FutureOr<void> Function() action) {
    return _persistOptimistically(value, next, (v) => value = v, action);
  }
}

@riverpod
Stream<List<Profile>> profilesStream(Ref ref) {
  return database.profilesDao.query().watch();
}

@riverpod
Stream<List<Rule>> addedRulesStream(Ref ref, int profileId) {
  return database.rulesDao.queryAddedRules(profileId).watch();
}

@riverpod
Stream<int> customRulesCount(Ref ref, int profileId) {
  return database.rulesDao.profileCustomRulesCount(profileId).watchSingle();
}

@riverpod
Stream<int> proxyGroupsCount(Ref ref, int profileId) {
  return database.proxyGroupsDao.count(profileId).watchSingle();
}

@Riverpod(keepAlive: true)
class Profiles extends _$Profiles {
  @override
  List<Profile> build() {
    return ref.watch(profilesStreamProvider).value ?? [];
  }

  /// [OptimisticMixin.optimistic] for this notifier, which keeps a plain list
  /// rather than an [AsyncValue].
  void _optimistic(List<Profile> next, FutureOr<void> Function() action) {
    unawaited(_optimisticAsync(next, action));
  }

  Future<void> _optimisticAsync(
    List<Profile> next,
    FutureOr<void> Function() action,
  ) {
    return _persistOptimistically(state, next, (v) => state = v, action);
  }

  void put(Profile profile) {
    final newProfile = state.optimizeLabel(profile);
    _optimistic(
      state.copyAndPut(newProfile, (item) => item.id == newProfile.id),
      () => database.profiles.put(newProfile.toCompanion()),
    );
  }

  Future<void> del(int id) {
    return _optimisticAsync(
      state.where((e) => e.id != id).toList(),
      () => database.profiles.remove((t) => t.id.equals(id)),
    );
  }

  void updateProfile(int profileId, Profile Function(Profile profile) builder) {
    final index = state.indexWhere((element) => element.id == profileId);
    if (index == -1) return;
    final newProfile = builder(state[index]);
    final next = List<Profile>.from(state);
    next[index] = newProfile;
    _optimistic(next, () => database.profiles.put(newProfile.toCompanion()));
  }

  void setAndReorder(List<Profile> profiles) {
    _optimistic(
      List<Profile>.from(profiles),
      () => database.profilesDao.setAll(profiles),
    );
  }

  void reorder(List<Profile> profiles) {
    final next = List<Profile>.from(profiles);
    final needUpdate = <ProfilesCompanion>[];
    next.forEachIndexed((index, item) {
      if (item.order != index) {
        needUpdate.add(item.toCompanion(index));
      }
    });
    _optimistic(next, () => database.profilesDao.putAll(needUpdate));
  }

  @override
  bool updateShouldNotify(List<Profile> previous, List<Profile> next) {
    return !profileListEquality.equals(previous, next);
  }
}

@riverpod
class Scripts extends _$Scripts with AsyncNotifierMixin, OptimisticMixin {
  @override
  Stream<List<Script>> build() {
    return database.scriptsDao.query().watch();
  }

  @override
  List<Script> get value => state.value ?? [];

  void put(Script script) {
    final next = List<Script>.from(value);
    final index = next.indexWhere((item) => item.id == script.id);
    if (index != -1) {
      next[index] = script;
    } else {
      next.add(script);
    }
    optimistic(next, () => database.scripts.put(script.toCompanion()));
  }

  void del(int id) {
    final next = List<Script>.from(value);
    final index = next.indexWhere((item) => item.id == id);
    if (index == -1) return;
    next.removeAt(index);
    optimistic(next, () => database.scripts.remove((t) => t.id.equals(id)));
  }

  bool isExits(String label) {
    return value.indexWhere((item) => item.label == label) != -1;
  }

  @override
  bool updateShouldNotify(
    AsyncValue<List<Script>> previous,
    AsyncValue<List<Script>> next,
  ) {
    return !scriptListEquality.equals(previous.value, next.value);
  }
}

@riverpod
Future<Script?> script(Ref ref, int? scriptId) async {
  final script = ref.watch(
    scriptsProvider.future.select((state) async {
      final scripts = await state;
      return scripts.get(scriptId);
    }),
  );
  return script;
}

@riverpod
class GlobalRules extends _$GlobalRules
    with AsyncNotifierMixin, OptimisticMixin {
  @override
  Stream<List<Rule>> build() {
    return database.rulesDao.queryGlobalAddedRules().watch();
  }

  @override
  List<Rule> get value => state.value ?? [];

  @override
  bool updateShouldNotify(
    AsyncValue<List<Rule>> previous,
    AsyncValue<List<Rule>> next,
  ) {
    return !ruleListEquality.equals(previous.value, next.value);
  }

  void delAll(Iterable<int> ruleIds) {
    optimistic(
      value.where((item) => !ruleIds.contains(item.id)).toList(),
      () => database.rulesDao.delRules(ruleIds),
    );
  }

  void put(Rule rule) {
    final newRule = rule.autoOrder(rule, null, value.firstOrNull?.order);
    optimistic(
      value.copyAndPut(newRule, (rule) => rule.id == newRule.id),
      () => database.rulesDao.putGlobalRule(newRule),
    );
  }

  void order(int oldIndex, int newIndex) {
    final item = value[oldIndex];
    final nextItems = value.copyAndReorder(oldIndex, newIndex);
    final newOrder = indexing.generateKeyBetween(
      nextItems.safeGet(newIndex - 1)?.order,
      nextItems.safeGet(newIndex + 1)?.order,
    )!;
    optimistic(
      nextItems,
      () => database.rulesDao.orderGlobalRule(ruleId: item.id, order: newOrder),
    );
  }
}

@riverpod
class ProfileAddedRules extends _$ProfileAddedRules
    with AsyncNotifierMixin, OptimisticMixin {
  @override
  Stream<List<Rule>> build(int profileId) {
    return database.rulesDao.queryProfileAddedRules(profileId).watch();
  }

  @override
  List<Rule> get value => state.value ?? [];

  @override
  bool updateShouldNotify(
    AsyncValue<List<Rule>> previous,
    AsyncValue<List<Rule>> next,
  ) {
    return !ruleListEquality.equals(previous.value, next.value);
  }

  void put(Rule rule) {
    final newRule = rule.autoOrder(rule, null, value.firstOrNull?.order);
    optimistic(
      value.copyAndPut(newRule, (rule) => rule.id == newRule.id),
      () => database.rulesDao.putProfileAddedRule(profileId, newRule),
    );
  }

  void delAll(Iterable<int> ruleIds) {
    optimistic(
      value.where((item) => !ruleIds.contains(item.id)).toList(),
      () => database.rulesDao.delRules(ruleIds),
    );
  }

  void order(int oldIndex, int newIndex) {
    final item = value[oldIndex];
    final nextItems = value.copyAndReorder(oldIndex, newIndex);
    final newOrder = indexing.generateKeyBetween(
      nextItems.safeGet(newIndex - 1)?.order,
      nextItems.safeGet(newIndex + 1)?.order,
    )!;
    optimistic(
      nextItems,
      () => database.rulesDao.orderProfileAddedRule(
        profileId,
        ruleId: item.id,
        order: newOrder,
      ),
    );
  }
}

@riverpod
class ProfileCustomRules extends _$ProfileCustomRules
    with AsyncNotifierMixin, OptimisticMixin {
  @override
  Stream<List<Rule>> build(int profileId) {
    return database.rulesDao.queryProfileCustomRules(profileId).watch();
  }

  @override
  List<Rule> get value => state.value ?? [];

  @override
  bool updateShouldNotify(
    AsyncValue<List<Rule>> previous,
    AsyncValue<List<Rule>> next,
  ) {
    return !ruleListEquality.equals(previous.value, next.value);
  }

  void put(Rule rule) {
    final newRule = rule.autoOrder(rule, null, value.firstOrNull?.order);
    optimistic(
      value.copyAndPut(newRule, (rule) => rule.id == newRule.id),
      () => database.rulesDao.putProfileCustomRule(profileId, newRule),
    );
  }

  void delAll(Iterable<int> ruleIds) {
    optimistic(
      value.where((item) => !ruleIds.contains(item.id)).toList(),
      () => database.rulesDao.delRules(ruleIds),
    );
  }

  void order(int oldIndex, int newIndex) {
    final item = value[oldIndex];
    final nextItems = value.copyAndReorder(oldIndex, newIndex);
    final newOrder = indexing.generateKeyBetween(
      nextItems.safeGet(newIndex - 1)?.order,
      nextItems.safeGet(newIndex + 1)?.order,
    )!;
    optimistic(
      nextItems,
      () => database.rulesDao.orderProfileCustomRule(
        profileId,
        ruleId: item.id,
        order: newOrder,
      ),
    );
  }
}

@riverpod
class ProxyGroups extends _$ProxyGroups
    with AsyncNotifierMixin, OptimisticMixin {
  @override
  Stream<List<ProxyGroup>> build(int profileId) {
    return database.proxyGroupsDao.query(profileId).watch();
  }

  @override
  bool updateShouldNotify(
    AsyncValue<List<ProxyGroup>> previous,
    AsyncValue<List<ProxyGroup>> next,
  ) {
    return !proxyGroupsEquality.equals(previous.value, next.value);
  }

  void del(String name) {
    optimistic(
      value.where((item) => item.name != name).toList(),
      () => database.proxyGroups.remove(
        (t) => t.profileId.equals(profileId) & t.name.equals(name),
      ),
    );
  }

  bool put(ProxyGroup proxyGroup) {
    final previous = value;
    final index = previous.indexWhere((item) => item.id == proxyGroup.id);
    if (index == -1 &&
        previous.indexWhere((item) => item.name == proxyGroup.name) != -1) {
      return false;
    }
    if (index != -1) {
      final oldName = previous[index].name;
      final newName = proxyGroup.name;
      if (oldName != newName) {
        database.rulesDao.renameCustomRuleTarget(
          profileId,
          oldName: oldName,
          newName: newName,
        );
        database.proxyGroupsDao.renameProxies(
          profileId,
          oldName: oldName,
          newName: newName,
        );
      }
    }
    final icon = proxyGroup.icon?.value;
    if (icon != null) {
      database.iconRecordsDao.put(icon);
    }
    final next = List<ProxyGroup>.from(previous);
    final ProxyGroup nextProxyGroup;
    if (index != -1) {
      nextProxyGroup = proxyGroup;
      next[index] = nextProxyGroup;
    } else {
      // A new group is appended, so its key has to sort after the last one that
      // already has one. Rows are ordered with nulls last, so the trailing
      // non-null order is the largest.
      final lastOrder = previous.map((item) => item.order).nonNulls.lastOrNull;
      nextProxyGroup = proxyGroup.copyWith(
        order: indexing.generateKeyBetween(lastOrder, null),
      );
      next.add(nextProxyGroup);
    }
    // Persist the ordered copy: writing `proxyGroup` back would drop the key
    // that was just handed to the optimistic state, leaving the row with a null
    // order forever.
    optimistic(
      next,
      () => database.proxyGroups.put(nextProxyGroup.toCompanion(profileId)),
    );
    return true;
  }

  void order(int oldIndex, int newIndex) {
    final item = value[oldIndex];
    final nextItems = value.copyAndReorder(oldIndex, newIndex);
    final newOrder = indexing.generateKeyBetween(
      nextItems.safeGet(newIndex - 1)?.order,
      nextItems.safeGet(newIndex + 1)?.order,
    )!;
    optimistic(
      nextItems,
      () => database.proxyGroupsDao.order(
        profileId,
        proxyGroup: item,
        order: newOrder,
      ),
    );
  }

  @override
  List<ProxyGroup> get value => state.value ?? [];
}

@riverpod
class ProfileDisabledRuleIds extends _$ProfileDisabledRuleIds
    with AsyncNotifierMixin, OptimisticMixin {
  @override
  List<int> get value => state.value ?? [];

  @override
  Stream<List<int>> build(int profileId) {
    return database.rulesDao
        .queryProfileDisabledRules(profileId)
        .map((item) => item.id)
        .watch();
  }

  @override
  bool updateShouldNotify(
    AsyncValue<List<int>> previous,
    AsyncValue<List<int>> next,
  ) {
    return !intListEquality.equals(previous.value, next.value);
  }

  void del(int ruleId) {
    optimistic(
      value.where((item) => item != ruleId).toList(),
      () => database.rulesDao.delDisabledLink(profileId, ruleId),
    );
  }

  void put(int ruleId) {
    final next = List<int>.from(value);
    if (!next.contains(ruleId)) {
      next.insert(0, ruleId);
    }
    optimistic(
      next,
      () => database.rulesDao.putDisabledLink(profileId, ruleId),
    );
  }
}
