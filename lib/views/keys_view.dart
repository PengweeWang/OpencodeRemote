import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/ssh_key_entry.dart';
import '../services/storage_service.dart';
import '../src/rust/api/simple.dart' as rust_api;
import '../theme/app_theme.dart';

class KeysView extends StatefulWidget {
  const KeysView({super.key});

  @override
  State<KeysView> createState() => _KeysViewState();
}

class _KeysViewState extends State<KeysView> {
  @override
  Widget build(BuildContext context) {
    final storage = StorageService();

    return AnimatedBuilder(
      animation: storage,
      builder: (context, _) {
        final keys = storage.keys;

        return Scaffold(
          appBar: AppBar(
            title: const Text('SSH 密钥管理'),
            actions: [
              IconButton(
                icon: const Icon(Icons.add),
                tooltip: '添加密钥',
                onPressed: () => _showAddKeyOptions(context),
              ),
            ],
          ),
          body: keys.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.key_outlined,
                        size: 64,
                        color: AppTheme.textSecondary,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '暂无 SSH 密钥',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '可以生成新的密钥对，或导入已有私钥',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('新建密钥'),
                        onPressed: () => _showGenerateKeyDialog(context),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: keys.length,
                  itemBuilder: (context, index) {
                    final key = keys[index];
                    return _buildKeyCard(context, key);
                  },
                ),
        );
      },
    );
  }

  Widget _buildKeyCard(BuildContext context, SshKeyEntry key) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.primary.withOpacity(0.4)),
                  ),
                  child: Text(
                    key.algorithm,
                    style: const TextStyle(
                      color: AppTheme.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    key.name,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (key.isEncrypted)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.lock, size: 16, color: Colors.amber),
                  ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  tooltip: '复制公钥',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: key.publicKeyOpenSsh));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('公钥已复制到剪贴板，可粘贴至服务器 ~/.ssh/authorized_keys'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20, color: AppTheme.error),
                  tooltip: '删除密钥',
                  onPressed: () => _confirmDeleteKey(context, key),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '指纹: ${key.fingerprintSha256}',
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
                fontFamily: 'monospace',
              ),
            ),
            if (key.comment.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '注释: ${key.comment}',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAddKeyOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.add_circle_outline, color: AppTheme.primary),
                title: const Text('生成新密钥对', style: TextStyle(color: AppTheme.textPrimary)),
                subtitle: const Text('生成 Ed25519 或 RSA 密钥', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showGenerateKeyDialog(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_download_outlined, color: AppTheme.accent),
                title: const Text('导入已有私钥', style: TextStyle(color: AppTheme.textPrimary)),
                subtitle: const Text('粘贴 OpenSSH 格式私钥文本', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showImportKeyDialog(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showGenerateKeyDialog(BuildContext context) {
    final nameCtrl = TextEditingController(text: 'Key-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}');
    final commentCtrl = TextEditingController(text: 'opencode-remote');
    final passCtrl = TextEditingController();
    String algo = 'ed25519';

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: AppTheme.surface,
          title: const Text('生成新 SSH 密钥', style: TextStyle(color: AppTheme.textPrimary)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: '密钥名称'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: algo,
                  decoration: const InputDecoration(labelText: '算法'),
                  items: const [
                    DropdownMenuItem(value: 'ed25519', child: Text('ED25519 (推荐，安全高效)')),
                    DropdownMenuItem(value: 'rsa2048', child: Text('RSA 2048')),
                    DropdownMenuItem(value: 'rsa4096', child: Text('RSA 4096')),
                    DropdownMenuItem(value: 'ecdsa', child: Text('ECDSA (P-256)')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => algo = val);
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: commentCtrl,
                  decoration: const InputDecoration(labelText: '注释 (可选)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码短语 (可选加密私钥)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;

                final pass = passCtrl.text.trim();
                final passphrase = pass.isNotEmpty ? pass : null;

                try {
                  final result = rust_api.generateKeyPair(
                    algorithm: algo,
                    comment: commentCtrl.text.trim(),
                    passphrase: passphrase,
                  );

                  final newEntry = SshKeyEntry(
                    id: 'key_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    algorithm: result.algorithm,
                    comment: result.comment,
                    publicKeyOpenSsh: result.publicKeyOpenssh,
                    privateKeyOpenSsh: result.privateKeyOpenssh,
                    fingerprintSha256: result.fingerprintSha256,
                    isEncrypted: result.isEncrypted,
                    passphrase: passphrase,
                  );

                  StorageService().saveKey(newEntry);
                  Navigator.pop(dialogCtx);

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('密钥 "${newEntry.name}" 生成成功！'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('生成失败: $e'),
                      backgroundColor: AppTheme.error,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              },
              child: const Text('生成'),
            ),
          ],
        ),
      ),
    );
  }

  void _showImportKeyDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('导入私钥', style: TextStyle(color: AppTheme.textPrimary)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '密钥名称', hintText: '例如: id_ed25519'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: keyCtrl,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'OpenSSH 私钥内容',
                  hintText: '-----BEGIN OPENSSH PRIVATE KEY-----...',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码短语 (若私钥已加密请输入)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final rawKey = keyCtrl.text.trim();
              if (name.isEmpty || rawKey.isEmpty) return;

              final pass = passCtrl.text.trim();
              final passphrase = pass.isNotEmpty ? pass : null;

              try {
                final result = rust_api.parseKeyPair(
                  privateKeyOpenssh: rawKey,
                  passphrase: passphrase,
                );

                final newEntry = SshKeyEntry(
                  id: 'key_${DateTime.now().millisecondsSinceEpoch}',
                  name: name,
                  algorithm: result.algorithm,
                  comment: result.comment,
                  publicKeyOpenSsh: result.publicKeyOpenssh,
                  privateKeyOpenSsh: result.privateKeyOpenssh,
                  fingerprintSha256: result.fingerprintSha256,
                  isEncrypted: result.isEncrypted,
                  passphrase: passphrase,
                );

                StorageService().saveKey(newEntry);
                Navigator.pop(dialogCtx);

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('私钥 "${newEntry.name}" 导入成功！'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('导入解析失败: $e'),
                    backgroundColor: AppTheme.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteKey(BuildContext context, SshKeyEntry key) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('删除密钥', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('确定要删除密钥 "${key.name}" 吗？', style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () {
              StorageService().deleteKey(key.id);
              Navigator.pop(dialogCtx);
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
