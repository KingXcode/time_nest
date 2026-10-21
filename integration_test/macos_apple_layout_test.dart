import 'package:integration_test/integration_test.dart';

import '../test/apple_components_test.dart' as components;
import '../test/apple_page_layout_test.dart' as pages;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  components.main();
  pages.main();
}
