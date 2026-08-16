part of '../action.dart';

@Riverpod(keepAlive: true)
class ProxiesAction extends _$ProxiesAction {
  CoreController get _core => ref.read(coreHandlerProvider);

  @override
  void build() {}

  void updateGroupsDebounce([Duration? duration]) {
    debouncer.call(FunctionTag.updateGroups, updateGroups, duration: duration);
  }

  void changeProxyDebounce(String groupName, String proxyName) {
    debouncer.call(FunctionTag.changeProxy, (
      String groupName,
      String proxyName,
    ) async {
      await changeProxy(groupName: groupName, proxyName: proxyName);
      updateGroupsDebounce();
    }, args: [groupName, proxyName]);
  }

  Future<void> updateGroups() async {
    try {
      commonPrint.log('updateGroups');
      ref.read(groupsProvider.notifier).value = await retry(
        task: () async {
          final sortType = ref.read(
            proxiesStyleSettingProvider.select((state) => state.sortType),
          );
          final delayMap = ref.read(delayDataSourceProvider);
          final testUrl = ref.read(
            appSettingProvider.select((state) => state.testUrl),
          );
          final selectedMap = ref.read(
            currentProfileProvider.select((state) => state?.selectedMap ?? {}),
          );
          return _core.getProxiesGroups(
            selectedMap: selectedMap,
            sortType: sortType,
            delayMap: delayMap,
            defaultTestUrl: testUrl,
          );
        },
        retryIf: (res) => res.isEmpty,
      );
    } catch (e) {
      // The groups already on screen are still the best answer we have; a core
      // hiccup should not empty the user's proxy list.
      commonPrint.log(
        'updateGroups error: $e',
        logLevel: coreFailureLogLevel(e),
      );
    }
  }

  void updateCurrentGroupName(String groupName) {
    final profile = ref.read(currentProfileProvider);
    if (profile == null || profile.currentGroupName == groupName) return;
    ref
        .read(profilesProvider.notifier)
        .put(profile.copyWith(currentGroupName: groupName));
  }

  void updateCurrentUnfoldSet(Set<String> value) {
    final currentProfile = ref.read(currentProfileProvider);
    if (currentProfile == null) return;
    ref
        .read(profilesProvider.notifier)
        .put(currentProfile.copyWith(unfoldSet: value));
  }

  void setDelay(Delay delay) {
    ref.read(delayDataSourceProvider.notifier).setDelay(delay);
  }

  Future<void> changeProxy({
    required String groupName,
    required String proxyName,
  }) async {
    await _core.changeProxy(
      ChangeProxyParams(groupName: groupName, proxyName: proxyName),
    );
    if (ref.read(appSettingProvider).closeConnections) {
      await _core.closeConnections();
    } else {
      await _core.resetConnections();
    }
    ref.read(checkIpNumProvider.notifier).add();
  }

  Future<String> updateProvider(
    ExternalProvider provider, {
    bool showLoading = false,
  }) async {
    try {
      if (showLoading) {
        ref.read(isUpdatingProvider(provider.updatingKey).notifier).value =
            true;
      }
      final message = await _core.updateExternalProvider(
        providerName: provider.name,
      );
      if (message.isNotEmpty) return message;
      ref
          .read(providersProvider.notifier)
          .setProvider(await _core.getExternalProvider(provider.name));
      return '';
    } finally {
      ref.read(isUpdatingProvider(provider.updatingKey).notifier).value = false;
    }
  }

  Future<String> sideLoadExternalProvider(
    ExternalProvider provider,
    String data,
  ) async {
    final message = await _core.sideLoadExternalProvider(
      providerName: provider.name,
      data: data,
    );
    if (message.isNotEmpty) return message;
    ref
        .read(providersProvider.notifier)
        .setProvider(await _core.getExternalProvider(provider.name));
    return '';
  }

  Future<void> proxyDelayTest(Proxy proxy, [String? testUrl]) async {
    final groups = ref.read(groupsProvider);
    final selectedMap = ref.read(
      currentProfileProvider.select((state) => state?.selectedMap ?? {}),
    );
    final state = computeRealSelectedProxyState(
      proxy.name,
      groups: groups,
      selectedMap: selectedMap,
    );
    final currentTestUrl = state.testUrl.takeFirstValid([
      ref.read(realTestUrlProvider(testUrl)),
    ]);
    if (state.proxyName.isEmpty) {
      return;
    }
    setDelay(Delay(url: currentTestUrl, name: state.proxyName, value: 0));
    try {
      final delay = await _core.getDelay(currentTestUrl, state.proxyName);
      setDelay(delay);
    } catch (error) {
      commonPrint.log(
        'Delay test failed for ${state.proxyName}: $error',
        logLevel: coreFailureLogLevel(error),
      );
      setDelay(Delay(url: currentTestUrl, name: state.proxyName, value: -1));
    }
  }

  Future<void> delayTest(List<Proxy> proxies, [String? testUrl]) async {
    final batches = proxies.batch(maxConcurrentDelayTests);
    for (final batch in batches) {
      await Future.wait(
        batch.map((proxy) async {
          await proxyDelayTest(proxy, testUrl);
        }),
      );
    }
    ref.read(sortNumProvider.notifier).add();
  }
}
