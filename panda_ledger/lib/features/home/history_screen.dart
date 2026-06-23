import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/snackbar_utils.dart';
import '../../core/widgets/record_card.dart';
import '../../data/local/app_database_provider.dart';
import '../../data/local/database.dart';
import '../../data/repository/record_repository.dart';
import '../record/record_screen.dart';

/// 历史流水页面 —— 搜索 / 筛选 / 按天分组 / 分页 / 编辑 / 删除
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  // 数据
  final List<Record> _records = [];
  bool _hasMore = true;
  bool _loading = false;
  bool _initialLoaded = false;

  // 分页
  static const _pageSize = 30;

  // 筛选状态
  DateTimeRange? _dateRange;
  String? _filterCategoryId;
  String? _filterAccountId;
  String? _keyword;

  // 分类 / 账户列表（用于筛选器）
  List<Category> _categories = [];
  List<Account> _accounts = [];

  // 分类/账户名称 + 图标缓存（避免 N+1 查询）
  final Map<String, String> _catNames = {};
  final Map<String, String?> _catIcons = {};
  final Map<String, String> _acctNames = {};

  // 搜索控制器
  final _searchCtrl = TextEditingController();

  // ScrollController for load-more
  final _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadFilterOptions();
      _loadRecords(reset: true);
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >= _scrollCtrl.position.maxScrollExtent - 200 &&
        !_loading && _hasMore) {
      _loadRecords();
    }
  }

  Future<void> _loadFilterOptions() async {
    final catDao = ref.read(categoryDaoProvider);
    final acctDao = ref.read(accountDaoProvider);
    final cats = await catDao.getActiveCategories();
    final accts = await acctDao.getActiveAccounts();
    if (mounted) {
      setState(() {
        _categories = cats;
        _accounts = accts;
      });
    }
  }

  Future<void> _loadRecords({bool reset = false}) async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final repo = ref.read(recordRepositoryProvider);
      final result = await repo.searchRecords(
        start: _dateRange?.start,
        end: _dateRange?.end != null
            ? _dateRange!.end.add(const Duration(days: 1))
            : null,
        categoryId: _filterCategoryId,
        accountId: _filterAccountId,
        keyword: _keyword,
        limit: _pageSize,
        offset: reset ? 0 : _records.length,
      );

      if (mounted) {
        setState(() {
          if (reset) {
            _records.clear();
            _catNames.clear();
            _catIcons.clear();
            _acctNames.clear();
          }
          _records.addAll(result.records);
          _hasMore = result.hasMore;
          _loading = false;
          _initialLoaded = true;
        });
        // 批量获取分类/账户名称
        _fetchNames(result.records);
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 批量获取 records 中未缓存的分类名和账户名
  Future<void> _fetchNames(List<Record> records) async {
    final catDao = ref.read(categoryDaoProvider);
    final acctDao = ref.read(accountDaoProvider);

    // 收集需要查询的 ID
    final catIds = <String>{};
    final acctIds = <String>{};
    for (final r in records) {
      if (r.categoryId != null && !_catNames.containsKey(r.categoryId)) {
        catIds.add(r.categoryId!);
      }
      if (!_acctNames.containsKey(r.accountId)) {
        acctIds.add(r.accountId);
      }
    }

    // 批量查询
    if (catIds.isNotEmpty) {
      final cats = await Future.wait(
        catIds.map((id) => catDao.getById(id)),
      );
      for (final c in cats) {
        if (c != null) {
          _catNames[c.id] = c.name;
          _catIcons[c.id] = c.icon;
        }
      }
    }
    if (acctIds.isNotEmpty) {
      final accts = await Future.wait(
        acctIds.map((id) => acctDao.getById(id)),
      );
      for (final a in accts) {
        if (a != null) {
          _acctNames[a.id] = a.name;
        }
      }
    }

    // 更新 UI 以显示名称
    if (mounted) setState(() {});
  }

  Future<void> _onRefresh() async {
    await _loadRecords(reset: true);
  }

  // ═══ 删除 ═══
  /// 删除流水 — Undo 模式：直接删除 + SnackBar 撤销，无弹窗确认。
  /// 返回 true 使 Dismissible 滑走卡片，false 弹回。
  Future<bool> _deleteRecord(Record record) async {
    try {
      final repo = ref.read(recordRepositoryProvider);
      await repo.deleteRecord(record);
      setState(() => _records.removeWhere((r) => r.id == record.id));

      if (!mounted) return true;

      SnackbarUtils.showUndo(
        context: context,
        message: '已删除 ¥${record.amount.toStringAsFixed(2)}',
        duration: const Duration(seconds: 5),
        onUndo: () async {
          try {
            await repo.restoreRecord(record);
            if (mounted) setState(() => _records.insert(0, record));
          } catch (e) {
            if (mounted) {
              SnackbarUtils.showError(context: context, message: '撤销失败: $e');
            }
          }
        },
      );

      return true;
    } catch (e) {
      if (mounted) {
        SnackbarUtils.showError(context: context, message: '删除失败: $e');
      }
      return false;
    }
  }

  // ═══ 编辑 ═══
  void _editRecord(Record record) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RecordScreen(editRecord: record)),
    );
    _loadRecords(reset: true);
  }

  // ═══ 筛选器弹窗 ═══
  void _showFilterSheet() {
    String? catId = _filterCategoryId;
    String? acctId = _filterAccountId;
    DateTimeRange? range = _dateRange;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (ctx, scrollCtrl) => SingleChildScrollView(
            controller: scrollCtrl,
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant.withAlpha(60),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('筛选条件', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 20),

                // 时间范围
                Text('时间范围', style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.date_range, size: 18),
                  label: Text(range == null
                      ? '全部时间'
                      : '${range!.start.month}/${range!.start.day} - ${range!.end.month}/${range!.end.day}'),
                  onPressed: () async {
                    final picked = await showDateRangePicker(
                      context: ctx,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) {
                      setSheetState(() => range = picked);
                    }
                  },
                ),
                if (range != null)
                  TextButton(
                    onPressed: () => setSheetState(() => range = null),
                    child: const Text('清除时间筛选'),
                  ),
                const SizedBox(height: 16),

                // 分类筛选
                Text('分类', style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 4,
                  children: [
                    FilterChip(
                      label: const Text('全部'),
                      selected: catId == null,
                      onSelected: (_) => setSheetState(() => catId = null),
                    ),
                    ..._categories.map((c) => FilterChip(
                          label: Text(c.name),
                          selected: catId == c.id,
                          onSelected: (_) => setSheetState(() => catId = c.id),
                        )),
                  ],
                ),
                const SizedBox(height: 16),

                // 账户筛选
                Text('账户', style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8, runSpacing: 4,
                  children: [
                    FilterChip(
                      label: const Text('全部'),
                      selected: acctId == null,
                      onSelected: (_) => setSheetState(() => acctId = null),
                    ),
                    ..._accounts.map((a) => FilterChip(
                          label: Text(a.name),
                          selected: acctId == a.id,
                          onSelected: (_) => setSheetState(() => acctId = a.id),
                        )),
                  ],
                ),
                const SizedBox(height: 24),

                // 应用按钮
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        _dateRange = range;
                        _filterCategoryId = catId;
                        _filterAccountId = acctId;
                      });
                      Navigator.pop(ctx);
                      _loadRecords(reset: true);
                    },
                    child: const Text('应用筛选'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasActiveFilter =>
      _dateRange != null || _filterCategoryId != null || _filterAccountId != null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('历史流水'),
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: '搜索备注…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _keyword != null && _keyword!.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _keyword = null);
                                _loadRecords(reset: true);
                              },
                            )
                          : null,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      isDense: true,
                    ),
                    onSubmitted: (v) {
                      setState(() => _keyword = v.trim().isEmpty ? null : v.trim());
                      _loadRecords(reset: true);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // 筛选按钮
                Badge(
                  isLabelVisible: _hasActiveFilter,
                  child: IconButton(
                    icon: Icon(
                      Icons.filter_list,
                      color: _hasActiveFilter ? theme.colorScheme.primary : null,
                    ),
                    onPressed: _showFilterSheet,
                    tooltip: '筛选',
                  ),
                ),
              ],
            ),
          ),

          // 数据列表
          Expanded(
            child: _initialLoaded && _records.isEmpty
                ? ListView(
                    // need scroll for pull-to-refresh
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.4,
                        child: Center(
                          child: Text('暂无记录', style: theme.textTheme.bodyMedium),
                        ),
                      ),
                    ],
                  )
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    child: ListView.builder(
                      controller: _scrollCtrl,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                      itemCount: _records.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        // loading indicator at bottom
                        if (index >= _records.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }

                        // day grouping logic: show header when date changes
                        final record = _records[index];
                        final dateKey = _dateKey(record.occurredAt);
                        final showHeader = index == 0 ||
                            _dateKey(_records[index - 1].occurredAt) != dateKey;

                        final catName = _catNames[record.categoryId] ?? '未分类';
                        final catIcon = record.categoryId != null
                            ? _catIcons[record.categoryId]
                            : null;
                        final acctName =
                            _acctNames[record.accountId] ?? '未知账户';

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (showHeader) _DayHeader(date: record.occurredAt, theme: theme),
                            RecordCard(
                              id: record.id,
                              type: record.type,
                              amount: record.amount,
                              categoryName: catName,
                              categoryIcon: catIcon,
                              accountName: acctName,
                              note: record.note,
                              syncStatus: record.syncStatus,
                              onTap: () => _editRecord(record),
                              onDelete: () => _deleteRecord(record),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// 日期分组标题
class _DayHeader extends StatelessWidget {
  final DateTime date;
  final ThemeData theme;
  const _DayHeader({required this.date, required this.theme});

  @override
  Widget build(BuildContext context) {
    final weekdayNames = ['一', '二', '三', '四', '五', '六', '日'];
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Text(
        '${date.month}月${date.day}日 周${weekdayNames[date.weekday - 1]}',
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
