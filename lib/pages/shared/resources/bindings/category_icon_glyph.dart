import 'package:beecount_ui/beecount_ui.dart';
import 'package:flutter/material.dart';
import '../../../category/editor/bindings/category_line_icon_names.dart';

/// 预设图标的两种存法：
///   * 旧持久化键（`restaurant`）/ lucide 名（`Utensils`）→ 单色线框，跟随调用方色；
///   * `color:<Glyph>` → 固定强调色的彩色图标，两台手机、重装后完全一致。
class CategoryIconStyle {
  static const String prefix = 'color:';

  static bool isColored(String? icon) =>
      icon != null && icon.startsWith(prefix);

  /// 实际用于渲染的 lucide 图标名。
  static String glyphOf(String? icon) {
    if (icon == null || icon.isEmpty) return 'Shapes';
    if (isColored(icon)) {
      final glyph = icon.substring(prefix.length);
      return glyph.isEmpty ? 'Shapes' : glyph;
    }
    return categoryLineIconNames[icon] ?? 'Shapes';
  }

  /// 彩色图标的强调色；单色图标返回 null。
  static Color? accentOf(String? icon) =>
      isColored(icon) ? coloredAccents[glyphOf(icon)] : null;

  /// 彩色组用到的固定色，键是 lucide 名，与存储值一一对应。
  static const Map<String, Color> coloredAccents = {
    'Utensils': Color(0xFFE8743B),
    'Coffee': Color(0xFF8A5A3B),
    'Pizza': Color(0xFFD9480F),
    'CakeSlice': Color(0xFFE64980),
    'Soup': Color(0xFFF08C00),
    'Fish': Color(0xFF1C7ED6),
    'IceCreamBowl': Color(0xFFF06595),
    'ShoppingCart': Color(0xFF12A594),
    'ShoppingBag': Color(0xFFE5484D),
    'ShoppingBasket': Color(0xFF0CA678),
    'Store': Color(0xFF2F9E44),
    'Car': Color(0xFF2E7BF6),
    'Bus': Color(0xFF3B5BDB),
    'TrainFront': Color(0xFF4263EB),
    'Plane': Color(0xFF1098AD),
    'Fuel': Color(0xFFE67700),
    'Ship': Color(0xFF0C8599),
    'Bike': Color(0xFF37B24D),
    'House': Color(0xFFC2703D),
    'Building2': Color(0xFF495057),
    'Zap': Color(0xFFF2B705),
    'Droplet': Color(0xFF0E9AA7),
    'Smartphone': Color(0xFF7048E8),
    'Wifi': Color(0xFF4C6EF5),
    'Headphones': Color(0xFF5F3DC4),
    'Hospital': Color(0xFFE03131),
    'Pill': Color(0xFFD6336C),
    'Dumbbell': Color(0xFFF76707),
    'GraduationCap': Color(0xFF7048E8),
    'BookOpen': Color(0xFF1971C2),
    'PawPrint': Color(0xFFA0622D),
    'Gamepad2': Color(0xFF5F3DC4),
    'Clapperboard': Color(0xFF495057),
    'Music': Color(0xFFBE4BDB),
    'Scissors': Color(0xFFE64980),
    'Shirt': Color(0xFFC2255C),
    'Gift': Color(0xFFE8590C),
    'Banknote': Color(0xFF2F9E44),
    'Landmark': Color(0xFF1864AB),
    'TrendingUp': Color(0xFF0CA678),
    'BriefcaseBusiness': Color(0xFF364FC7),
    'FerrisWheel': Color(0xFFF06595),
    'ShieldCheck': Color(0xFF1098AD),
    'Baby': Color(0xFFF783AC),
    'Ticket': Color(0xFF7C5CFC),
  };
}

/// 分类图标的统一画法：彩色图标画成「淡底圆角块 + 强调色线框」；
/// 尺寸过小（< 16）时退化为纯强调色线框，避免糊成一团。
class CategoryIconGlyph extends StatelessWidget {
  const CategoryIconGlyph(
      {super.key, required this.icon, this.size = 20, this.color});

  /// 存库的原始值（旧键 / lucide 名 / `color:` 前缀）。
  final String? icon;
  final double size;

  /// 单色图标的自定义色；彩色图标忽略它。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = CategoryIconStyle.accentOf(icon);
    final glyph = CategoryIconStyle.glyphOf(icon);
    if (accent == null || size < 16) {
      return BeeLineIcon(glyph, size: size, color: accent ?? color);
    }
    return SizedBox(
      width: size,
      height: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
            color: accent.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(size * .3)),
        child: Center(
            child: BeeLineIcon(glyph, size: size * .64, color: accent)),
      ),
    );
  }
}
