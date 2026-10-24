import 'package:flutter/material.dart';
import '../models/ssh_host.dart';
import '../services/opencode_service.dart';
import '../theme/app_theme.dart';
import '../views/webview_view.dart';

class ConnectionProgressSheet extends StatefulWidget {
  final SshHost host;

  const ConnectionProgressSheet({super.key, required this.host});

  static Future<void> show(BuildContext context, SshHost host) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.surface,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ConnectionProgressSheet(host: host),
    );
  }

  @override
  State<ConnectionProgressSheet> createState() => _ConnectionProgressSheetState();
}

class _ConnectionProgressSheetState extends State<ConnectionProgressSheet> {
  final ScrollController _logScrollController = ScrollController();
  bool _autoNavigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startConnecting();
    });
  }

  void _startConnecting() {
    final service = OpencodeService();
    _autoNavigated = false;
    service.connect(widget.host);
  }

  @override
  void dispose() {
    _logScrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = OpencodeService();

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final state = service.state;
        final logs = service.logs;
        _scrollToBottom();

        // Check if ready and navigate to WebView automatically
        if (state == OpencodeState.ready && !_autoNavigated) {
          _autoNavigated = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.pop(context); // Close progress sheet
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const OpencodeWebViewScreen()),
              );
            }
          });
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.rocket_launch, color: AppTheme.primary, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '正在连接 ${widget.host.name}',
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${widget.host.username}@${widget.host.host}:${widget.host.port}',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (state == OpencodeState.error)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      )
                  ],
                ),
                const SizedBox(height: 20),

                // Step Progression
                _buildStepItem(
                  title: '建立 SSH 安全通道',
                  isDone: state != OpencodeState.connecting && state != OpencodeState.error && state != OpencodeState.idle,
                  isActive: state == OpencodeState.connecting,
                  isError: state == OpencodeState.error && logs.any((l) => l.step == 'connecting' || l.step == 'init'),
                ),
                _buildStepItem(
                  title: '检查 Opencode 核心服务状态',
                  isDone: state == OpencodeState.startingService ||
                      state == OpencodeState.pairing ||
                      state == OpencodeState.forwarding ||
                      state == OpencodeState.ready,
                  isActive: state == OpencodeState.checkingService,
                  isError: state == OpencodeState.error && logs.any((l) => l.step == 'checking'),
                ),
                _buildStepItem(
                  title: '启动服务 (未开启则自动启动)',
                  isDone: state == OpencodeState.pairing ||
                      state == OpencodeState.forwarding ||
                      state == OpencodeState.ready,
                  isActive: state == OpencodeState.startingService,
                  isError: state == OpencodeState.error && logs.any((l) => l.step == 'starting_service'),
                ),
                _buildStepItem(
                  title: '获取配对链接 (opencode pair)',
                  isDone: state == OpencodeState.forwarding || state == OpencodeState.ready,
                  isActive: state == OpencodeState.pairing,
                  isError: state == OpencodeState.error && logs.any((l) => l.step == 'pairing'),
                ),
                _buildStepItem(
                  title: '建立本地端口转发与 UI 加载',
                  isDone: state == OpencodeState.ready,
                  isActive: state == OpencodeState.forwarding,
                  isError: state == OpencodeState.error && logs.any((l) => l.step == 'forwarding'),
                ),

                const SizedBox(height: 16),
                const Text(
                  '实时运行日志:',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 130,
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: ListView.builder(
                    controller: _logScrollController,
                    itemCount: logs.length,
                    itemBuilder: (ctx, idx) {
                      final l = logs[idx];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '[${l.timeFormatted}] ${l.message}',
                          style: TextStyle(
                            color: l.isError ? AppTheme.error : AppTheme.textSecondary,
                            fontSize: 11,
                            fontFamily: 'monospace',
                          ),
                        ),
                      );
                    },
                  ),
                ),

                const SizedBox(height: 16),
                if (state == OpencodeState.error) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('关闭'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('重试连接'),
                          onPressed: _startConnecting,
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () {
                        service.disconnect();
                        Navigator.pop(context);
                      },
                      child: const Text('取消连接'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStepItem({
    required String title,
    required bool isDone,
    required bool isActive,
    required bool isError,
  }) {
    Widget icon;
    if (isError) {
      icon = const Icon(Icons.cancel, color: AppTheme.error, size: 18);
    } else if (isDone) {
      icon = const Icon(Icons.check_circle, color: AppTheme.accent, size: 18);
    } else if (isActive) {
      icon = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
      );
    } else {
      icon = const Icon(Icons.radio_button_unchecked, color: AppTheme.border, size: 18);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: isError
                    ? AppTheme.error
                    : isActive || isDone
                        ? AppTheme.textPrimary
                        : AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
