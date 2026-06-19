import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'assets_provider.dart';

/// 净资产趋势曲线
///
/// 使用 fl_chart 绘制平滑曲线，最新数据点高亮。
/// 支持日/周/月/年/自定义多种时间维度的标签显示。
class NetWorthChart extends StatefulWidget {
  /// 数据点列表
  final List<SnapshotPoint> data;
  final int initialPointsToShow;

  const NetWorthChart({
    super.key,
    required this.data,
    this.initialPointsToShow = 6,
  });

  @override
  State<NetWorthChart> createState() => _NetWorthChartState();
}

class _NetWorthChartState extends State<NetWorthChart> {
  late int _pointsToShow;

  @override
  void initState() {
    super.initState();
    _pointsToShow = widget.initialPointsToShow;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = widget.data;

    if (data.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart, size: 40, color: theme.colorScheme.outline),
            const SizedBox(height: 8),
            Text('记录余额变化后显示趋势', style: theme.textTheme.bodySmall),
          ],
        ),
      );
    }

    // 过滤显示范围
    final showData = data.length <= _pointsToShow
        ? data
        : data.sublist(data.length - _pointsToShow);

    if (showData.isEmpty) return const SizedBox(height: 160);

    final spots = showData.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.netWorth);
    }).toList();

    // 计算 Y 轴范围
    final values = showData.map((d) => d.netWorth);
    final minY = values.reduce((a, b) => a < b ? a : b);
    final maxY = values.reduce((a, b) => a > b ? a : b);
    final padding = (maxY - minY) * 0.2;
    final yMin = minY == maxY ? minY - 100 : minY - padding;
    final yMax = minY == maxY ? maxY + 100 : maxY + padding;

    // 判断趋势方向
    final isUpward = showData.last.netWorth >= showData.first.netWorth;

    // X轴标签间隔（自动调整避免重叠）
    final labelInterval = showData.length > 20
        ? (showData.length / 4).ceil()
        : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 显示范围选择器
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: _rangeOptions(data.length).map((opt) {
            final selected = _pointsToShow == opt;
            return Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ActionChip(
                label: Text('$opt项', style: const TextStyle(fontSize: 12)),
                onPressed: () => setState(() => _pointsToShow = opt),
                backgroundColor: selected
                    ? theme.colorScheme.primaryContainer
                    : null,
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 12),

        // 曲线图
        Semantics(
          label: '净资产趋势图，显示最近$_pointsToShow个数据点。'
              '当前净资产¥${showData.last.netWorth.toStringAsFixed(0)}，'
              '${isUpward ? "呈上升趋势" : "呈下降趋势"}。',
          child: SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minY: yMin,
                maxY: yMax,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (yMax - yMin) / 4,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: theme.colorScheme.outlineVariant.withAlpha(80),
                    strokeWidth: 0.5,
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval: labelInterval.toDouble(),
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= showData.length) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            showData[idx].label,
                            style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.outline),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      interval: (yMax - yMin) / 4,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          _formatAmount(value),
                          style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.outline),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          '¥ ${spot.y.toStringAsFixed(0)}',
                          TextStyle(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: isUpward
                        ? theme.colorScheme.primary
                        : theme.colorScheme.error,
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: showData.length <= 31,
                      getDotPainter: (spot, _, _, _) {
                        final isLast = spot.x == spots.last.x;
                        return FlDotCirclePainter(
                          radius: isLast ? 5 : 2,
                          color: isLast
                              ? (isUpward
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.error)
                              : theme.colorScheme.outline.withAlpha(160),
                          strokeWidth: isLast ? 2 : 0,
                          strokeColor: theme.colorScheme.surface,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      color: (isUpward
                              ? theme.colorScheme.primary
                              : theme.colorScheme.error)
                          .withAlpha(25),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 根据数据量生成范围选项
  List<int> _rangeOptions(int total) {
    if (total <= 6) return [total];
    if (total <= 12) return [6, total];
    if (total <= 30) return [7, 14, total];
    if (total <= 60) return [12, 30, total];
    return [12, total ~/ 2, total];
  }

  String _formatAmount(double value) {
    if (value.abs() >= 10000) {
      return '${(value / 10000).toStringAsFixed(1)}万';
    }
    if (value.abs() >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}k';
    }
    return value.toStringAsFixed(0);
  }
}
