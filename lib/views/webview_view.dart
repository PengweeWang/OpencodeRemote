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
                // Ignore benign canceled requests
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

  Future<void> _handleRefreshPairUrl() async {
    final service = OpencodeService();
    try {
      final newUrl = await service.refreshPairUrl();
      await _controller.loadRequest(Uri.parse(newUrl));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已重新获取配对 Token 并刷新页面'),
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

  Future<void> _openExternalBrowser() async {
    final urlStr = OpencodeService().localUrl;
    if (urlStr != null) {
      final uri = Uri.parse(urlStr);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
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

  Future<bool> _confirmDisconnect() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('断开连接', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          '确定要断开与 Opencode 的远程会话吗？',
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

    if (result == true) {
      await OpencodeService().disconnect();
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final service = OpencodeService();
    final host = service.currentHost;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          final shouldExit = await _confirmDisconnect();
          if (shouldExit && mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回/断开',
            onPressed: () async {
              final shouldExit = await _confirmDisconnect();
              if (shouldExit && mounted) {
                Navigator.of(context).pop();
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
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: '刷新页面',
              onPressed: () => _controller.reload(),
            ),
            IconButton(
              icon: const Icon(Icons.key, size: 20),
              tooltip: '重新获取配对 Token',
              onPressed: _handleRefreshPairUrl,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              color: AppTheme.surface,
              onSelected: (val) async {
                switch (val) {
                  case 'external':
                    _openExternalBrowser();
                    break;
                  case 'logs':
                    _showLogsSheet(context);
                    break;
                  case 'restart_service':
                    try {
                      await service.controlService('restart');
                      await _handleRefreshPairUrl();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('重启失败: $e'),
                          backgroundColor: AppTheme.error,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                    break;
                  case 'stop_service':
                    try {
                      await service.controlService('stop');
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已停止远程 Opencode 服务'),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('停止服务失败: $e'),
                          backgroundColor: AppTheme.error,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    }
                    break;
                  case 'disconnect':
                    final exit = await _confirmDisconnect();
                    if (exit && mounted) {
                      Navigator.of(context).pop();
                    }
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'external',
                  child: Row(
                    children: [
                      Icon(Icons.open_in_browser, size: 18),
                      SizedBox(width: 8),
                      Text('在外部浏览器中打开'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'logs',
                  child: Row(
                    children: [
                      Icon(Icons.list_alt, size: 18),
                      SizedBox(width: 8),
                      Text('查看运行日志'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'restart_service',
                  child: Row(
                    children: [
                      Icon(Icons.restart_alt, size: 18),
                      SizedBox(width: 8),
                      Text('重启远程服务'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'stop_service',
                  child: Row(
                    children: [
                      Icon(Icons.stop_circle_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('停止远程服务'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'disconnect',
                  child: Row(
                    children: [
                      Icon(Icons.power_settings_new, size: 18, color: AppTheme.error),
                      SizedBox(width: 8),
                      Text('断开连接', style: TextStyle(color: AppTheme.error)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
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
              WebViewWidget(controller: _controller),
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
          ],
        ),
      ),
    );
  }
}
