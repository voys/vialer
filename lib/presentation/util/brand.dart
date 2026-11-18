import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../data/models/user/brand.dart';

extension BrandContext on BuildContext {
  Brand get brand => Provider.of<Brand>(this, listen: false);
}
