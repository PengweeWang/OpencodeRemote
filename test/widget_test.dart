import 'package:flutter_test/flutter_test.dart';
import 'package:opencode_remote/models/ssh_host.dart';
import 'package:opencode_remote/models/ssh_key_entry.dart';

void main() {
  test('SshHost serialization test', () {
    final host = SshHost(
      id: 'host_test_1',
      name: 'Server 1',
      host: '192.168.1.10',
      port: 22,
      username: 'user1',
      authType: 'password',
      password: 'mypassword',
      remoteWorkdir: '/home/user1/work',
    );

    final json = host.toJson();
    final restored = SshHost.fromJson(json);

    expect(restored.id, 'host_test_1');
    expect(restored.name, 'Server 1');
    expect(restored.host, '192.168.1.10');
    expect(restored.port, 22);
    expect(restored.username, 'user1');
    expect(restored.password, 'mypassword');
    expect(restored.remoteWorkdir, '/home/user1/work');
  });

  test('SshKeyEntry serialization test', () {
    final key = SshKeyEntry(
      id: 'key_test_1',
      name: 'My Ed25519 Key',
      algorithm: 'ED25519',
      publicKeyOpenSsh: 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...',
      privateKeyOpenSsh: '-----BEGIN OPENSSH PRIVATE KEY-----\n...',
      fingerprintSha256: 'SHA256:abcd...',
    );

    final json = key.toJson();
    final restored = SshKeyEntry.fromJson(json);

    expect(restored.id, 'key_test_1');
    expect(restored.name, 'My Ed25519 Key');
    expect(restored.algorithm, 'ED25519');
    expect(restored.publicKeyOpenSsh, 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5...');
  });
}
