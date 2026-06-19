/// UUID v4 生成器
///
/// 使用 `Random.secure()` 生成符合 RFC 4122 的 UUID v4。
/// 在自用场景下提供足够强的唯一性保证，避免依赖外部 `uuid` 包。
library;

import 'dart:math';

class IdGenerator {
  IdGenerator._();

  static final _random = Random.secure();

  static String generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));

    // UUID v4: 第 7 字节高 4 位固定为 0100 (version 4)
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    // UUID v4: 第 9 字节高 2 位固定为 10 (variant 1)
    bytes[8] = (bytes[8] & 0x3F) | 0x80;

    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }
}
