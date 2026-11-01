import 'package:flutter/material.dart';

/// Physical directions used throughout Mishkat: opening/next is `>`, while
/// returning/previous is `<`. These glyphs do not mirror with text direction.
abstract final class MishkatNavigationIcons {
  static const IconData forward = Icons.keyboard_arrow_right_rounded;
  static const IconData back = Icons.keyboard_arrow_left_rounded;
}
