import 'package:flutter/material.dart';
import '../models/ssh_host.dart';
import '../services/keepalive_service.dart';
import '../services/opencode_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../widgets/connection_progress_sheet.dart';
import '../widgets/host_form_dialog.dart';
import 'keys_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with WidgetsBindingObserver {
  bool _isIgnoringBattery = true;
  bool _showBatteryNotice = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkBatteryOptimizations();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkBatteryOptimizations();
    }
  }

  Future<void> _checkBatteryOptimizations() async {
    final isIgnoring = await KeepAliveService().isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() {
        _isIgnoringBattery = isIgnoring;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = StorageService();

    return AnimatedBuilder(
      animation: storage,
      builder: (context, _) {
        final hosts = storage.hosts;
        final lastHost = storage.lastHost;

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 32,
                    height: 32,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Opencode Remote',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.key_outlined),
                tooltip: 'SSH 密钥',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const KeysView()),
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: '添加主机',
                onPressed: () => _openHostForm(context),
              ),
            ],
          ),
          body: hosts.isEmpty
              ? _buildEmptyState(context)
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (!_isIgnoringBattery && _showBatteryNotice) ...[
                      _buildBatteryNoticeCard(context),
                      const SizedBox(height: 16),
                    ],
                    if (lastHost != null) ...[
                      _buildQuickConnectCard(context, lastHost),
                      const SizedBox(height: 20),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          '所有远程主机',
                          style: TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '共 ${hosts.length} 个配置',
                          style: const TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...hosts.map((h) => _buildHostCard(context, h)),
                  ],
                ),
          floatingActionButton: hosts.isNotEmpty
              ? FloatingActionButton.extended(
                  backgroundColor: AppTheme.primary,
                  icon: const Icon(Icons.add),
                  label: const Text('添加主机'),
                  onPressed: () => _openHostForm(context),
                )
              : null,
        );
      },
    );
  }

  Widget _buildBatteryNoticeCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primary.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Icon(Icons.battery_saver, color: AppTheme.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '后台持续保活建议',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  '为避免切换后台或息屏时系统中断 SSH 会话与端口转发，建议允许忽略电池优化。',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 11, height: 1.4),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => KeepAliveService().requestIgnoreBatteryOptimizations(),
                      child: const Text('允许忽略优化', style: TextStyle(fontSize: 11)),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => setState(() => _showBatteryNotice = false),
                      child: const Text('暂不需要', style: TextStyle(color: AppTheme.textSecondary, fontSize: 11)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: AppTheme.textSecondary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _showBatteryNotice = false),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (!_isIgnoringBattery && _showBatteryNotice) ...[
              _buildBatteryNoticeCard(context),
              const SizedBox(height: 24),
            ],
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.border),
              ),
              child: const Icon(
                Icons.computer_outlined,
                size: 64,
                color: AppTheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '欢迎使用 Opencode Remote',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '通过 SSH 连接远程服务器，自动检查并启动 Opencode 核心服务，通过端口转发直接在 Android 应用内打开 Web UI。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('添加第一个远程主机'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              onPressed: () => _openHostForm(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickConnectCard(BuildContext context, SshHost host) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryDark.withOpacity(0.4),
            AppTheme.surface,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primary.withOpacity(0.5), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, size: 16, color: AppTheme.primary),
                const SizedBox(width: 6),
                const Text(
                  '最近连接',
                  style: TextStyle(
                    color: AppTheme.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (host.lastConnected != null)
                  Text(
                    _formatTime(host.lastConnected!),
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              host.name,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${host.username}@${host.host}:${host.port}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('快速连接并打开 Opencode'),
                onPressed: () => _connectHost(context, host),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHostCard(BuildContext context, SshHost host) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Icon(Icons.dns_outlined, color: AppTheme.primary, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    host.name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${host.username}@${host.host}:${host.port}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: host.authType == 'key'
                              ? AppTheme.accent.withOpacity(0.15)
                              : Colors.amber.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          host.authType == 'key' ? 'SSH 密钥' : '密码登录',
                          style: TextStyle(
                            color: host.authType == 'key' ? AppTheme.accent : Colors.amber,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (host.remoteWorkdir != null && host.remoteWorkdir!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            host.remoteWorkdir!,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
              onPressed: () => _connectHost(context, host),
              child: const Text('连接'),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 20),
              color: AppTheme.surface,
              onSelected: (val) {
                switch (val) {
                  case 'test':
                    _testHost(context, host);
                    break;
                  case 'edit':
                    _openHostForm(context, host: host);
                    break;
                  case 'delete':
                    _confirmDeleteHost(context, host);
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'test',
                  child: Row(
                    children: [
                      Icon(Icons.network_check, size: 18),
                      SizedBox(width: 8),
                      Text('测试连接'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18),
                      SizedBox(width: 8),
                      Text('编辑配置'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 18, color: AppTheme.error),
                      SizedBox(width: 8),
                      Text('删除', style: TextStyle(color: AppTheme.error)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openHostForm(BuildContext context, {SshHost? host}) {
    showDialog<SshHost>(
      context: context,
      builder: (_) => HostFormDialog(host: host),
    );
  }

  void _connectHost(BuildContext context, SshHost host) {
    ConnectionProgressSheet.show(context, host);
  }

  Future<void> _testHost(BuildContext context, SshHost host) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在测试连接 ${host.host}:${host.port}...'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final msg = await OpencodeService().testHost(host);
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: AppTheme.accent),
              SizedBox(width: 8),
              Text('连接成功', style: TextStyle(color: AppTheme.textPrimary)),
            ],
          ),
          content: Text(msg, style: const TextStyle(color: AppTheme.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('好的'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: AppTheme.error),
              SizedBox(width: 8),
              Text('连接失败', style: TextStyle(color: AppTheme.textPrimary)),
            ],
          ),
          content: Text(e.toString(), style: const TextStyle(color: AppTheme.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('关闭'),
            ),
          ],
        ),
      );
    }
  }

  void _confirmDeleteHost(BuildContext context, SshHost host) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('删除配置', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('确定要删除配置 "${host.name}" 吗？', style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () {
              StorageService().deleteHost(host.id);
              Navigator.pop(dialogCtx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    return '${dt.month}月${dt.day}日';
  }
}
