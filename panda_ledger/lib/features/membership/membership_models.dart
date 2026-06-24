/// 会员体系数据模型
library;

// ─────────────────────────────────────────────
// MembershipSku — 对应 membership_skus 表一行
// ─────────────────────────────────────────────

class MembershipSku {
  final String id;
  final String skuCode;
  final String title;
  final String subtitle;
  final int priceCents;
  final int? originalPriceCents;
  final int? durationDays;
  final String planType;
  final String? badge;
  final int sortOrder;

  const MembershipSku({
    required this.id,
    required this.skuCode,
    required this.title,
    required this.subtitle,
    required this.priceCents,
    this.originalPriceCents,
    this.durationDays,
    required this.planType,
    this.badge,
    required this.sortOrder,
  });

  factory MembershipSku.fromJson(Map<String, dynamic> json) {
    return MembershipSku(
      id: json['id'] as String,
      skuCode: json['sku_code'] as String,
      title: json['title'] as String,
      subtitle: (json['subtitle'] as String?) ?? '',
      priceCents: json['price_cents'] as int,
      originalPriceCents: json['original_price_cents'] as int?,
      durationDays: json['duration_days'] as int?,
      planType: json['plan_type'] as String,
      badge: json['badge'] as String?,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  /// 展示价格字符串，如 "¥18.00"
  String get priceLabel => '¥${(priceCents / 100).toStringAsFixed(2)}'
      .replaceAll(RegExp(r'\.00$'), '');

  /// 划线原价字符串
  String? get originalPriceLabel {
    if (originalPriceCents == null) return null;
    return '¥${(originalPriceCents! / 100).toStringAsFixed(2)}'
        .replaceAll(RegExp(r'\.00$'), '');
  }

  /// 有效期描述，如 "30天" / "365天" / "永久"
  String get durationLabel {
    if (durationDays == null) return '永久';
    if (durationDays! >= 365) return '${durationDays! ~/ 365} 年';
    return '$durationDays 天';
  }
}

// ─────────────────────────────────────────────
// MembershipInfo — 对应 memberships 表一行（客户端视图）
// ─────────────────────────────────────────────

class MembershipInfo {
  final String plan;      // monthly / yearly / lifetime
  final String status;    // active / expired / refunded
  final DateTime? expiresAt;
  final String source;

  const MembershipInfo({
    required this.plan,
    required this.status,
    this.expiresAt,
    required this.source,
  });

  factory MembershipInfo.fromJson(Map<String, dynamic> json) {
    return MembershipInfo(
      plan: json['plan'] as String,
      status: json['status'] as String,
      source: json['source'] as String,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String).toLocal()
          : null,
    );
  }

  /// 是否真正有效（status=active 且未过期）
  bool get isActive {
    if (status != 'active') return false;
    if (expiresAt == null) return true; // 永久
    return expiresAt!.isAfter(DateTime.now());
  }

  /// 到期描述，如 "2026-09-24 到期" / "永久有效"
  String get expiryLabel {
    if (expiresAt == null) return '永久有效';
    final d = expiresAt!;
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} 到期';
  }

  /// 档位中文名
  String get planLabel {
    switch (plan) {
      case 'monthly':
        return '月度会员';
      case 'yearly':
        return '年度会员';
      case 'lifetime':
        return '永久会员';
      default:
        return '会员';
    }
  }
}
