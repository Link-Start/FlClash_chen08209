// GENERATED CODE - DO NOT MODIFY BY HAND

part of '../core.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// The Core facade, reached through the container rather than the
/// `coreController` global.
///
/// Reading Core through a provider lets a test scope a fake to one container
/// with `overrideWithValue`, instead of swapping the process-wide singleton and
/// relying on a tearDown to put it back.

@ProviderFor(coreHandler)
final coreHandlerProvider = CoreHandlerProvider._();

/// The Core facade, reached through the container rather than the
/// `coreController` global.
///
/// Reading Core through a provider lets a test scope a fake to one container
/// with `overrideWithValue`, instead of swapping the process-wide singleton and
/// relying on a tearDown to put it back.

final class CoreHandlerProvider
    extends $FunctionalProvider<CoreController, CoreController, CoreController>
    with $Provider<CoreController> {
  /// The Core facade, reached through the container rather than the
  /// `coreController` global.
  ///
  /// Reading Core through a provider lets a test scope a fake to one container
  /// with `overrideWithValue`, instead of swapping the process-wide singleton and
  /// relying on a tearDown to put it back.
  CoreHandlerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'coreHandlerProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$coreHandlerHash();

  @$internal
  @override
  $ProviderElement<CoreController> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  CoreController create(Ref ref) {
    return coreHandler(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(CoreController value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<CoreController>(value),
    );
  }
}

String _$coreHandlerHash() => r'b00cbd733d546e4edd1a0b9b98e9ace46da1eff2';
