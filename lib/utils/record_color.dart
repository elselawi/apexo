import 'dart:ui' show Color;

import 'package:apexo/utils/colors_without_yellow.dart';
import 'package:apexo/utils/get_deterministic_item.dart';

/// The deterministic colour of a record, from its id.
///
/// This is what the legacy `Model.color` was: the same palette, the same hash,
/// the same result. It is a free function now because a row has no colour of
/// its own — and because deriving one is a display concern, not a schema one.
Color recordColor(String id) =>
    getDeterministicItem<Color>(colorsWithoutYellow, id);
