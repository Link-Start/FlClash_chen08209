import 'package:riverpod/misc.dart' show ProviderListenable;

// WidgetRef and ProviderContainer share no supertype, but their read methods
// have the same signature. Non-widget collaborators take this instead of
// reaching for a container, so callers pass whichever one they already hold.
typedef ProviderReader = T Function<T>(ProviderListenable<T> provider);
