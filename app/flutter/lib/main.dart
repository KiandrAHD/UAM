/// UAM application entry point.
///
/// All bootstrap work lives in `bootstrap.dart` so tests can construct the app
/// without launching the platform runner.
library;

import 'bootstrap.dart';

Future<void> main() async {
  await bootstrap();
}
