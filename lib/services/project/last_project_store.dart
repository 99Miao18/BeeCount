import 'package:shared_preferences/shared_preferences.dart';

/// 按账本记住「上次选的项目」。
///
/// 纯本地偏好，不进云端、不进数据库：项目本身（`◆` 前缀标签）走标签通道
/// 同步，这里只记「这台设备在这个账本里最近一次挂在哪个项目上」，用于新建
/// 账单时自动带出，避免旅行途中连记十笔每次都要手点。
///
/// 用字符串存 id 是因为共享账本的标签 id 是负数（synthetic id），
/// `setInt` 在部分平台对负数不友好，统一转字符串更稳。
///
/// 内存里再兜一层：保存后宿主会立刻重建编辑器（「保存并再记一笔」），
/// 只靠 SharedPreferences 的异步写入会与下一次读取竞争，读到的可能还是旧值。
class LastProjectStore {
  const LastProjectStore._();

  static final Map<int, int?> _memo = {};

  static String _key(int ledgerId) => 'lastProjectTagId.$ledgerId';

  static Future<int?> read(int ledgerId) async {
    if (_memo.containsKey(ledgerId)) return _memo[ledgerId];
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = int.tryParse(prefs.getString(_key(ledgerId)) ?? '');
      _memo[ledgerId] = value;
      return value;
    } catch (_) {
      // 读不到就当没记住（widget 测试里没有 SharedPreferences 插件）。
      return null;
    }
  }

  static Future<void> write(int ledgerId, int? tagId) async {
    _memo[ledgerId] = tagId;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (tagId == null) {
        await prefs.remove(_key(ledgerId));
      } else {
        await prefs.setString(_key(ledgerId), '$tagId');
      }
    } catch (_) {
      // 持久化失败不影响本次保存，下次只是不预填。
    }
  }
}
