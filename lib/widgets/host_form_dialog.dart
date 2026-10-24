import 'package:flutter/material.dart';
import '../models/ssh_host.dart';
import '../services/opencode_service.dart';
import '../services/storage_service.dart';
import '../theme/app_theme.dart';
import '../views/keys_view.dart';

class HostFormDialog extends StatefulWidget {
  final SshHost? host;

  const HostFormDialog({super.key, this.host});

  @override
  State<HostFormDialog> createState() => _HostFormDialogState();
}

class _HostFormDialogState extends State<HostFormDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _hostCtrl;
  late final TextEditingController _portCtrl;
  late final TextEditingController _userCtrl;
  late final TextEditingController _pwdCtrl;
  late final TextEditingController _passphraseCtrl;
  late final TextEditingController _workdirCtrl;
  late final TextEditingController _customCmdCtrl;
  late final TextEditingController _localPortCtrl;

  late String _authType;
  String? _selectedKeyId;
  bool _obscurePwd = true;
  bool _showAdvanced = false;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    final h = widget.host;
    _nameCtrl = TextEditingController(text: h?.name ?? '');
    _hostCtrl = TextEditingController(text: h?.host ?? '');
    _portCtrl = TextEditingController(text: h?.port.toString() ?? '22');
    _userCtrl = TextEditingController(text: h?.username ?? '');
    _pwdCtrl = TextEditingController(text: h?.password ?? '');
    _passphraseCtrl = TextEditingController(text: h?.passphrase ?? '');
    _workdirCtrl = TextEditingController(text: h?.remoteWorkdir ?? '');
    _customCmdCtrl = TextEditingController(text: h?.customOpencodePath ?? '');
    _localPortCtrl = TextEditingController(text: h?.preferredLocalPort?.toString() ?? '');

    _authType = h?.authType ?? 'password';
    _selectedKeyId = h?.keyId;

    if (_selectedKeyId == null && StorageService().keys.isNotEmpty) {
      _selectedKeyId = StorageService().keys.first.id;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _userCtrl.dispose();
    _pwdCtrl.dispose();
    _passphraseCtrl.dispose();
    _workdirCtrl.dispose();
    _customCmdCtrl.dispose();
    _localPortCtrl.dispose();
    super.dispose();
  }

  SshHost _buildHostFromForm() {
    return SshHost(
      id: widget.host?.id ?? 'host_${DateTime.now().millisecondsSinceEpoch}',
      name: _nameCtrl.text.trim().isEmpty ? _hostCtrl.text.trim() : _nameCtrl.text.trim(),
      host: _hostCtrl.text.trim(),
      port: int.tryParse(_portCtrl.text.trim()) ?? 22,
      username: _userCtrl.text.trim(),
      authType: _authType,
      password: _pwdCtrl.text.isNotEmpty ? _pwdCtrl.text : null,
      keyId: _authType == 'key' ? _selectedKeyId : null,
      passphrase: _passphraseCtrl.text.isNotEmpty ? _passphraseCtrl.text : null,
      remoteWorkdir: _workdirCtrl.text.trim().isNotEmpty ? _workdirCtrl.text.trim() : null,
      customOpencodePath: _customCmdCtrl.text.trim().isNotEmpty ? _customCmdCtrl.text.trim() : null,
      preferredLocalPort: int.tryParse(_localPortCtrl.text.trim()),
      lastConnected: widget.host?.lastConnected,
    );
  }

  Future<void> _testConnection() async {
    final host = _buildHostFromForm();
    if (host.host.isEmpty || host.username.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先填写主机地址和用户名'),
          backgroundColor: AppTheme.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isTesting = true);
    try {
      final msg = await OpencodeService().testHost(host);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: AppTheme.accent),
                SizedBox(width: 8),
                Text('SSH 连接成功', style: TextStyle(color: AppTheme.textPrimary)),
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
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppTheme.surface,
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: AppTheme.error),
                SizedBox(width: 8),
                Text('SSH 连接失败', style: TextStyle(color: AppTheme.textPrimary)),
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
    } finally {
      if (mounted) {
        setState(() => _isTesting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keys = StorageService().keys;

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.host == null ? '添加远程设备' : '编辑连接配置',
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '配置别名 (可选)',
                  hintText: '例如: 我的工作站 / GPU服务器',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _hostCtrl,
                      decoration: const InputDecoration(
                        labelText: '主机地址 *',
                        hintText: '192.168.1.100 或 example.com',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 1,
                    child: TextField(
                      controller: _portCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '端口 *'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _userCtrl,
                decoration: const InputDecoration(
                  labelText: 'SSH 用户名 *',
                  hintText: '例如: ubuntu / root',
                ),
              ),
              const SizedBox(height: 16),
              // Auth Type Selector
              const Text(
                '身份认证方式',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('密码认证')),
                      selected: _authType == 'password',
                      onSelected: (val) {
                        if (val) setState(() => _authType = 'password');
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ChoiceChip(
                      label: const Center(child: Text('SSH 密钥')),
                      selected: _authType == 'key',
                      onSelected: (val) {
                        if (val) setState(() => _authType = 'key');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_authType == 'password')
                TextField(
                  controller: _pwdCtrl,
                  obscureText: _obscurePwd,
                  decoration: InputDecoration(
                    labelText: 'SSH 登录密码',
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePwd ? Icons.visibility_off : Icons.visibility,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscurePwd = !_obscurePwd),
                    ),
                  ),
                )
              else ...[
                if (keys.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.background,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '当前没有保存的 SSH 密钥',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const KeysView()),
                            ).then((_) => setState(() {}));
                          },
                          child: const Text('去生成/导入'),
                        ),
                      ],
                    ),
                  )
                else
                  DropdownButtonFormField<String>(
                    value: keys.any((k) => k.id == _selectedKeyId)
                        ? _selectedKeyId
                        : keys.first.id,
                    decoration: const InputDecoration(labelText: '选择 SSH 密钥'),
                    items: keys.map((k) {
                      return DropdownMenuItem(
                        value: k.id,
                        child: Text('${k.name} (${k.algorithm})'),
                      );
                    }).toList(),
                    onChanged: (val) => setState(() => _selectedKeyId = val),
                  ),
                const SizedBox(height: 12),
                TextField(
                  controller: _passphraseCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '密钥密码短语 (可选)',
                    hintText: '若私钥已加密请填写',
                  ),
                ),
              ],
              const SizedBox(height: 16),
              // Collapsible Advanced Settings
              InkWell(
                onTap: () => setState(() => _showAdvanced = !_showAdvanced),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        _showAdvanced ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_right,
                        color: AppTheme.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'Opencode 高级启动选项',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_showAdvanced) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _workdirCtrl,
                  decoration: const InputDecoration(
                    labelText: '远程启动工作目录 (可选)',
                    hintText: '例如: ~/projects/my-web-app',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _customCmdCtrl,
                  decoration: const InputDecoration(
                    labelText: '自定义 Opencode 路径 (可选)',
                    hintText: '默认自动探测 ~/.opencode/bin/opencode',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _localPortCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '本地转发固定端口 (可选)',
                    hintText: '留空则自动分配空闲端口',
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  OutlinedButton.icon(
                    icon: _isTesting
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.network_check, size: 18),
                    label: const Text('测试连接'),
                    onPressed: _isTesting ? null : _testConnection,
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final host = _buildHostFromForm();
                      if (host.host.isEmpty || host.username.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('请填写主机地址和用户名'),
                            backgroundColor: AppTheme.error,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                        return;
                      }

                      StorageService().saveHost(host);
                      Navigator.pop(context, host);
                    },
                    child: const Text('保存配置'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
