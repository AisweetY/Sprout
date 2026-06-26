import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 全量初始化同步的阶段
enum SyncPhase { idle, syncing, done }

/// 同步状态快照
class SyncState {
  final SyncPhase phase;

  /// 同步完成时的简短摘要文本（仅 done 阶段有值）
  final String? message;

  const SyncState._({required this.phase, this.message});

  const SyncState.idle() : this._(phase: SyncPhase.idle);
  const SyncState.syncing() : this._(phase: SyncPhase.syncing);
  const SyncState.done(String msg)
      : this._(phase: SyncPhase.done, message: msg);

  bool get isSyncing => phase == SyncPhase.syncing;
  bool get isDone => phase == SyncPhase.done;
}

class SyncStateNotifier extends StateNotifier<SyncState> {
  SyncStateNotifier() : super(const SyncState.idle());

  void start() => state = const SyncState.syncing();
  void done(String message) => state = SyncState.done(message);
  void reset() => state = const SyncState.idle();
}

/// 全量同步状态 Provider
///
/// 仅在应用初始化（`app_shell._initialize()`）时更新；
/// 5 分钟定时同步保持静默，不改变此状态。
///
/// 消费方：
/// - `HomeScreen`：AppBar 下方进度条（isSyncing）+ SnackBar（isDone）
final syncStateProvider =
    StateNotifierProvider<SyncStateNotifier, SyncState>(
  (ref) => SyncStateNotifier(),
);
