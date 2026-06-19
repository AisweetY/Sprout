import 'package:flutter_test/flutter_test.dart';
import 'package:panda_ledger/features/insights/insights_provider.dart';

/// InsightsData 模型测试——验证模型正确存储和传递所有时间维度参数
void main() {
  group('InsightsData 完整模型', () {
    test('包含所有字段且 params 传递正确', () {
      final params = InsightsParams.monthly(2026, 6);
      final data = InsightsData(
        income: 10000,
        expense: 5000,
        netSaving: 5000,
        prevIncome: 9000,
        prevExpense: 4500,
        savingsRate: 50,
        rankings: [
          RankingItem(name: '餐饮', amount: 2000),
          RankingItem(name: '交通', amount: 1500),
        ],
        conclusion: '6月总支出 ¥5000，储蓄率 50%。最大支出是「餐饮」。',
        params: params,
      );

      expect(data.income, 10000);
      expect(data.expense, 5000);
      expect(data.netSaving, 5000);
      expect(data.savingsRate, 50);
      expect(data.rankings.length, 2);
      expect(data.rankings.first.name, '餐饮');
      expect(data.params.dimension, TimeDimension.month);
      expect(data.params.summaryTitle, '本月小结');
      expect(data.params.comparisonLabel, '上月');
      expect(data.params.comparisonTitle, '环比上月');
      expect(data.params.periodLabel, '2026年6月');
    });

    test('自定义维度 params 传递正确', () {
      final params = InsightsParams.custom(
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 20),
      );
      final data = InsightsData(
        income: 8000,
        expense: 3000,
        netSaving: 5000,
        prevIncome: 0,
        prevExpense: 0,
        savingsRate: 62.5,
        rankings: [],
        conclusion: '时段小结',
        params: params,
      );

      expect(data.params.dimension, TimeDimension.custom);
      expect(data.params.summaryTitle, '时段小结');
      expect(data.params.comparisonLabel, '上期');
      expect(data.params.comparisonTitle, '对比上期');
    });

    test('日维度 params 传递正确', () {
      final params = InsightsParams.daily(DateTime(2026, 6, 20));
      final data = InsightsData(
        income: 500,
        expense: 200,
        netSaving: 300,
        prevIncome: 0,
        prevExpense: 0,
        savingsRate: 60,
        rankings: [],
        conclusion: '日小结',
        params: params,
      );

      expect(data.params.dimension, TimeDimension.day);
      expect(data.params.summaryTitle, '本日小结');
      expect(data.params.comparisonLabel, '昨天');
      expect(data.params.comparisonTitle, '对比昨天');
    });
  });
}
