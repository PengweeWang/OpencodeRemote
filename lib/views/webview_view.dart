import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/opencode_service.dart';
import '../theme/app_theme.dart';

class OpencodeWebViewScreen extends StatefulWidget {
  const OpencodeWebViewScreen({super.key});

  @override
  State<OpencodeWebViewScreen> createState() => _OpencodeWebViewScreenState();
}

class _OpencodeWebViewScreenState extends State<OpencodeWebViewScreen> {
  late final WebViewController _controller;
  int _loadingProgress = 0;
  bool _isLoading = true;
  String? _loadError;
  bool _canPop = false;
  bool _isFullScreen = true;

  // Floating draggable control button position
  Offset? _fabPosition;

  @override
  void initState() {
    super.initState();
    final service = OpencodeService();
    final initialUrl = service.localUrl ?? '';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppTheme.background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (mounted) {
              setState(() {
                _loadingProgress = progress;
                _isLoading = progress < 100;
              });
            }
          },
          onPageStarted: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _loadError = null;
              });
            }
          },
          onPageFinished: (String url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onWebResourceError: (WebResourceError error) {
            if (mounted) {
              setState(() {
                // Ignore benign canceled requests (-999)
                if (error.errorCode != -999) {
                  _loadError = error.description;
                }
              });
            }
          },
        ),
      );

    if (initialUrl.isNotEmpty) {
      _controller.loadRequest(Uri.parse(initialUrl));
    }
  }

  // ---- Actions ----

  Future<void> _handleRefreshPairUrl() async {
    final service = OpencodeService();
    try {
      final newUrl = await service.refreshPairUrl();
      await _controller.loadRequest(Uri.parse(newUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已重新获取配对 Token 并刷新当前页面'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('刷新配对链接失败: $e'),
            backgroundColor: AppTheme.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// In external browser, we MUST re-pair a fresh token,
  /// otherwise Opencode rejects the used token with an error.
  Future<void> _openInExternalBrowser() async {
    final service = OpencodeService();
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('正在生成新的配对链接并在外部浏览器打开...')),
          ],
        ),
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      // Generate a fresh unconsumed pair link from remote server
      final freshUrl = await service.refreshPairUrl();
      final uri = Uri.parse(freshUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('无法调起系统外部浏览器');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('获取新配对链接并在浏览器打开失败: $e'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _disconnectAndExit() async {
    await OpencodeService().disconnect();
    if (!mounted) return;
    setState(() {
      _canPop = true;
    });
    Navigator.of(context).pop();
  }

  Future<bool> _confirmDisconnectDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('断开连接', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          '确定要断开与 Opencode 的远程会话并退出吗？',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('断开并退出'),
          ),
        ],
      ),
    );

    return result ?? false;
  }

  void _showLogsSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final logs = OpencodeService().logs;
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.3,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollController) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '连接与运行日志',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(color: AppTheme.border),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: logs.length,
                    itemBuilder: (context, idx) {
                      final log = logs[idx];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '[${log.timeFormatted}] ',
                              style: const TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: log.isError
                                    ? AppTheme.error.withOpacity(0.2)
                                    : AppTheme.primary.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                log.step,
                                style: TextStyle(
                                  color: log.isError ? AppTheme.error : AppTheme.primary,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                log.message,
                                style: TextStyle(
                                  color: log.isError ? AppTheme.error : AppTheme.textPrimary,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showControlSheet(BuildContext context) {
    final service = OpencodeService();
    final host = service.currentHost;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => SafeArea(
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
              // Session Status Header
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: AppTheme.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          host?.name ?? 'Opencode 远程会话',
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (service.localPort != null)
                          Text(
                            '本地 127.0.0.1:${service.localPort} ➔ 远程:${service.remotePort}',
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 12,
                              fontFamily: 'monospace',
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(sheetCtx),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: AppTheme.border, height: 1),
              const SizedBox(height: 12),

              // Action List
              ListTile(
                dense: true,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.open_in_browser, color: AppTheme.primary, size: 20),
                ),
                title: const Text('在外部浏览器打开', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: const Text('自动重新生成可用新配对链接并在外部浏览器开启', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _openInExternalBrowser();
                },
              ),
              ListTile(
                dense: true,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.refresh, color: AppTheme.primary, size: 20),
                ),
                title: const Text('刷新 WebView 页面', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _controller.reload();
                },
              ),
              ListTile(
                dense: true,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.key, color: Colors.amber, size: 20),
                ),
                title: const Text('重新获取配对 Token', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: const Text('若页面提示 Token 过期或失效可点击重新配对', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _handleRefreshPairUrl();
                },
              ),
              ListTile(
                dense: true,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.list_alt, color: AppTheme.primary, size: 20),
                ),
                title: const Text('查看运行日志', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  _showLogsSheet(context);
                },
              ),
              ListTile(
                dense: true,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.border.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.restart_alt, color: AppTheme.textPrimary, size: 20),
                ),
                title: const Text('重启远程服务', style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: const Text('执行 opencode service restart 并更新链接', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                onTap: () async {
                  Navigator.pop(sheetCtx);
                  try {
                    await service.controlService('restart');
                    await _handleRefreshPairUrl();
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('重启服务失败: $e'), backgroundColor: AppTheme.error),
                    );
                  }
                },
              ),
              ListTile(
                dense: true,
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    color: AppTheme.primary,
                    size: 20,
                  ),
                ),
                title: Text(
                  _isFullScreen ? '退出全屏 (显示顶部栏)' : '切换至全屏模式 (隐藏顶部栏)',
                  style: const TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                ),
                onTap: () {
                  Navigator.pop(sheetCtx);
                  setState(() => _isFullScreen = !_isFullScreen);
                },
              ),
              const SizedBox(height: 12),
              // Disconnect button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.error,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.power_settings_new, size: 20),
                  label: const Text('断开并退出'),
                  onPressed: () async {
                    Navigator.pop(sheetCtx);
                    final shouldExit = await _confirmDisconnectDialog();
                    if (shouldExit && mounted) {
                      await _disconnectAndExit();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final service = OpencodeService();
    final host = service.currentHost;
    final screenSize = MediaQuery.of(context).size;

    // Default floating control position at bottom right
    _fabPosition ??= Offset(screenSize.width - 64, screenSize.height - 130);

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          final shouldExit = await _confirmDisconnectDialog();
          if (shouldExit && mounted) {
            await _disconnectAndExit();
          }
        }
      },
      child: Scaffold(
        appBar: _isFullScreen
            ? null
            : AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: '断开并退出',
                  onPressed: () async {
                    final shouldExit = await _confirmDisconnectDialog();
                    if (shouldExit && mounted) {
                      await _disconnectAndExit();
                    }
                  },
                ),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppTheme.accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          host?.name ?? 'Opencode',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    if (service.localPort != null)
                      Text(
                        '127.0.0.1:${service.localPort} ➔ 远程:${service.remotePort}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontFamily: 'monospace',
                        ),
                      ),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.fullscreen, size: 22),
                    tooltip: '全屏模式',
                    onPressed: () => setState(() => _isFullScreen = true),
                  ),
                  IconButton(
                    icon: const Icon(Icons.tune, size: 20),
                    tooltip: '快捷控制菜单',
                    onPressed: () => _showControlSheet(context),
                  ),
                ],
              ),
        body: SafeArea(
          top: !_isFullScreen,
          bottom: false,
          child: Stack(
            children: [
              // 1. Fullscreen WebView
              if (_loadError != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.cloud_off, size: 64, color: AppTheme.textSecondary),
                        const SizedBox(height: 16),
                        const Text(
                          '网页加载遇到问题',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _loadError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                        ),
                        const SizedBox(height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              icon: const Icon(Icons.refresh, size: 18),
                              label: const Text('重试加载'),
                              onPressed: () {
                                setState(() => _loadError = null);
                                _controller.reload();
                              },
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.key, size: 18),
                              label: const Text('重新配对 Token'),
                              onPressed: _handleRefreshPairUrl,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                )
              else
                SizedBox.expand(
                  child: WebViewWidget(controller: _controller),
                ),

              // 2. Loading Progress Indicator
              if (_isLoading)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: _loadingProgress / 100.0,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                    minHeight: 2.5,
                  ),
                ),

              // 3. Floating Draggable Control Pill/Ball (Always accessible, especially in Full Screen)
              Positioned(
                left: (_fabPosition!.dx).clamp(10.0, screenSize.width - 58.0),
                top: (_fabPosition!.dy).clamp(30.0, screenSize.height - 70.0),
                child: GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _fabPosition = Offset(
                        _fabPosition!.dx + details.delta.dx,
                        _fabPosition!.dy + details.delta.dy,
                      );
                    });
                  },
                  child: Material(
                    elevation: 6,
                    color: AppTheme.surface.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(24),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(24),
                      onTap: () => _showControlSheet(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: AppTheme.primary.withOpacity(0.6), width: 1.2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppTheme.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.tune, color: AppTheme.textPrimary, size: 18),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
