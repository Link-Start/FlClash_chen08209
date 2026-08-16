import 'package:fl_clash/core/controller.dart';
import 'package:fl_clash/core/interface.dart';
import 'package:fl_clash/enum/enum.dart';
import 'package:fl_clash/models/models.dart';
import 'package:fl_clash/providers/action.dart';
import 'package:fl_clash/providers/app.dart';
import 'package:fl_clash/providers/config.dart';
import 'package:fl_clash/providers/core.dart';
import 'package:fl_clash/providers/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:riverpod/riverpod.dart';

import '../helpers/test_profiles.dart';

class MockCoreHandlerInterface extends Mock implements CoreHandlerInterface {}

const _testUrl = 'http://delay.test';

Group _group(String name, List<Proxy> all) =>
    Group(type: GroupType.Selector, name: name, all: all);

const _proxy = Proxy(name: 'HK-01', type: 'ss');

ExternalProvider _provider(String name, {int count = 1}) => ExternalProvider(
  name: name,
  type: 'Proxy',
  count: count,
  vehicleType: 'HTTP',
  updateAt: DateTime.utc(2026),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockCoreHandlerInterface core;

  setUpAll(() {
    registerFallbackValue(
      const ChangeProxyParams(groupName: 'G', proxyName: 'P'),
    );
    core = MockCoreHandlerInterface();
  });

  setUp(() => reset(core));

  ProviderContainer buildContainer({Profile? profile}) {
    final container = ProviderContainer(
      overrides: [
        coreHandlerProvider.overrideWithValue(CoreController.scoped(core)),
        profilesProvider.overrideWith(() => TestProfiles([?profile])),
        currentProfileIdProvider.overrideWithBuild((_, _) => profile?.id),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  ProxiesAction actionOf(ProviderContainer container) =>
      container.read(proxiesActionProvider.notifier);

  group('updateGroups', () {
    test('publishes the groups derived from core proxy data', () async {
      when(core.getProxies).thenAnswer(
        (_) async => ProxiesData(
          all: const ['Proxy', 'Direct'],
          proxies: Map<String, dynamic>.from({
            'Proxy': Map<String, dynamic>.from({
              'name': 'Proxy',
              'type': 'Selector',
              'now': 'HK-01',
              'all': ['HK-01'],
            }),
            'Direct': Map<String, dynamic>.from({
              'name': 'Direct',
              'type': 'Direct',
            }),
            'HK-01': Map<String, dynamic>.from({'name': 'HK-01', 'type': 'ss'}),
          }),
        ),
      );
      final container = buildContainer();

      await actionOf(container).updateGroups();

      final groups = container.read(groupsProvider);
      expect(groups.map((group) => group.name), ['Proxy']);
      expect(groups.single.all.map((proxy) => proxy.name), ['HK-01']);
    });

    test('keeps the groups already on screen when core throws', () async {
      when(core.getProxies).thenThrow(StateError('core down'));
      final container = buildContainer();
      container.read(groupsProvider.notifier).value = [
        _group('Stale', const []),
      ];

      await actionOf(container).updateGroups();

      // Stale groups beat no groups: a core hiccup used to empty the list the
      // user was looking at, and nothing refills it until the next update.
      expect(container.read(groupsProvider).map((group) => group.name), [
        'Stale',
      ]);
    });
  });

  group('changeProxy', () {
    setUp(() {
      when(() => core.changeProxy(any())).thenAnswer((_) async => '');
      when(core.closeConnections).thenAnswer((_) async => true);
      when(core.resetConnections).thenAnswer((_) async => true);
    });

    test('closes connections and bumps the ip check when enabled', () async {
      final container = buildContainer();
      container.read(appSettingProvider.notifier).value = const AppSettingProps(
        closeConnections: true,
      );
      final before = container.read(checkIpNumProvider);

      await actionOf(
        container,
      ).changeProxy(groupName: 'Proxy', proxyName: 'HK-01');

      verify(
        () => core.changeProxy(
          const ChangeProxyParams(groupName: 'Proxy', proxyName: 'HK-01'),
        ),
      ).called(1);
      verify(core.closeConnections).called(1);
      verifyNever(core.resetConnections);
      expect(container.read(checkIpNumProvider), before + 1);
    });

    test('resets connections instead when the setting is off', () async {
      final container = buildContainer();
      container.read(appSettingProvider.notifier).value = const AppSettingProps(
        closeConnections: false,
      );

      await actionOf(
        container,
      ).changeProxy(groupName: 'Proxy', proxyName: 'HK-01');

      verify(core.resetConnections).called(1);
      verifyNever(core.closeConnections);
    });
  });

  group('proxyDelayTest', () {
    test('records an in-progress zero then the measured delay', () async {
      final observed = <int?>[];
      when(() => core.asyncTestDelay(_testUrl, 'HK-01')).thenAnswer((_) async {
        observed.add(0);
        return const Delay(name: 'HK-01', url: _testUrl, value: 128);
      });
      final container = buildContainer();
      container.read(appSettingProvider.notifier).value = const AppSettingProps(
        testUrl: _testUrl,
      );

      await actionOf(container).proxyDelayTest(_proxy);

      expect(observed, [0]);
      expect(container.read(delayDataSourceProvider)[_testUrl]?['HK-01'], 128);
    });

    test('records -1 when the delay request fails', () async {
      when(
        () => core.asyncTestDelay(_testUrl, 'HK-01'),
      ).thenThrow(StateError('timeout'));
      final container = buildContainer();
      container.read(appSettingProvider.notifier).value = const AppSettingProps(
        testUrl: _testUrl,
      );

      await actionOf(container).proxyDelayTest(_proxy);

      expect(container.read(delayDataSourceProvider)[_testUrl]?['HK-01'], -1);
    });

    test('does nothing when the resolved proxy name is empty', () async {
      final container = buildContainer();

      await actionOf(container).proxyDelayTest(const Proxy(name: '', type: ''));

      expect(container.read(delayDataSourceProvider), isEmpty);
      verifyNever(() => core.asyncTestDelay(any(), any()));
    });
  });

  group('delayTest', () {
    test('measures every proxy and bumps the sort counter', () async {
      when(() => core.asyncTestDelay(_testUrl, any())).thenAnswer(
        (invocation) async => Delay(
          name: invocation.positionalArguments[1] as String,
          url: _testUrl,
          value: 10,
        ),
      );
      final container = buildContainer();
      container.read(appSettingProvider.notifier).value = const AppSettingProps(
        testUrl: _testUrl,
      );
      final before = container.read(sortNumProvider);

      await actionOf(
        container,
      ).delayTest(const [_proxy, Proxy(name: 'HK-02', type: 'ss')]);

      final delays = container.read(delayDataSourceProvider)[_testUrl];
      expect(delays?['HK-01'], 10);
      expect(delays?['HK-02'], 10);
      expect(container.read(sortNumProvider), before + 1);
    });
  });

  group('updateProvider', () {
    test(
      'stores the refreshed provider and clears the updating flag',
      () async {
        final refreshed = _provider('geo', count: 5);
        when(
          () => core.updateExternalProvider('geo'),
        ).thenAnswer((_) async => '');
        when(
          () => core.getExternalProvider('geo'),
        ).thenAnswer((_) async => refreshed);
        final container = buildContainer();
        container.read(providersProvider.notifier).value = [_provider('geo')];

        final message = await actionOf(
          container,
        ).updateProvider(_provider('geo'), showLoading: true);

        expect(message, isEmpty);
        expect(container.read(providersProvider), [refreshed]);
        expect(container.read(isUpdatingProvider('provider_geo')), isFalse);
      },
    );

    test('returns the core message without storing a provider', () async {
      when(
        () => core.updateExternalProvider('geo'),
      ).thenAnswer((_) async => 'update failed');
      final container = buildContainer();

      final message = await actionOf(
        container,
      ).updateProvider(_provider('geo'), showLoading: true);

      expect(message, 'update failed');
      expect(container.read(providersProvider), isEmpty);
      expect(container.read(isUpdatingProvider('provider_geo')), isFalse);
      verifyNever(() => core.getExternalProvider(any()));
    });

    test('clears the updating flag when core throws', () async {
      when(
        () => core.updateExternalProvider('geo'),
      ).thenThrow(StateError('boom'));
      final container = buildContainer();

      await expectLater(
        actionOf(container).updateProvider(_provider('geo'), showLoading: true),
        throwsStateError,
      );

      expect(container.read(isUpdatingProvider('provider_geo')), isFalse);
    });
  });

  group('sideLoadExternalProvider', () {
    test('stores the provider after a successful side load', () async {
      final refreshed = _provider('rules', count: 3);
      when(
        () => core.sideLoadExternalProvider(
          providerName: 'rules',
          data: 'payload',
        ),
      ).thenAnswer((_) async => '');
      when(
        () => core.getExternalProvider('rules'),
      ).thenAnswer((_) async => refreshed);
      final container = buildContainer();
      container.read(providersProvider.notifier).value = [_provider('rules')];

      final message = await actionOf(
        container,
      ).sideLoadExternalProvider(_provider('rules'), 'payload');

      expect(message, isEmpty);
      expect(container.read(providersProvider), [refreshed]);
    });

    test('surfaces the core message and skips the refresh', () async {
      when(
        () => core.sideLoadExternalProvider(providerName: 'rules', data: 'bad'),
      ).thenAnswer((_) async => 'invalid payload');
      final container = buildContainer();

      final message = await actionOf(
        container,
      ).sideLoadExternalProvider(_provider('rules'), 'bad');

      expect(message, 'invalid payload');
      verifyNever(() => core.getExternalProvider(any()));
    });
  });

  group('current profile mutations', () {
    test('updateCurrentGroupName writes the new group onto the profile', () {
      final profile = Profile.normal(label: 'p');
      final container = buildContainer(profile: profile);

      actionOf(container).updateCurrentGroupName('Proxy');

      expect(container.read(profilesProvider).single.currentGroupName, 'Proxy');
    });

    test('updateCurrentGroupName is a no-op for the same group', () {
      final profile = Profile.normal(
        label: 'p',
      ).copyWith(currentGroupName: 'Proxy');
      final container = buildContainer(profile: profile);

      actionOf(container).updateCurrentGroupName('Proxy');

      expect(container.read(profilesProvider).single, same(profile));
    });

    test('updateCurrentUnfoldSet is a no-op without a current profile', () {
      final container = buildContainer();

      expect(
        () => actionOf(container).updateCurrentUnfoldSet({'Proxy'}),
        returnsNormally,
      );
      expect(container.read(profilesProvider), isEmpty);
    });

    test('updateCurrentUnfoldSet stores the set on the current profile', () {
      final profile = Profile.normal(label: 'p');
      final container = buildContainer(profile: profile);

      actionOf(container).updateCurrentUnfoldSet({'Proxy', 'Auto'});

      expect(container.read(profilesProvider).single.unfoldSet, {
        'Proxy',
        'Auto',
      });
    });
  });
}
