import 'package:fl_clash/core/controller.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'generated/core.g.dart';

/// The Core facade, reached through the container rather than the
/// `coreController` global.
///
/// Reading Core through a provider lets a test scope a fake to one container
/// with `overrideWithValue`, instead of swapping the process-wide singleton and
/// relying on a tearDown to put it back.
@Riverpod(keepAlive: true)
CoreController coreHandler(Ref ref) => coreController;
