class SshKeyEntry {
  final String id;
  String name;
  String algorithm;
  String comment;
  String publicKeyOpenSsh;
  String privateKeyOpenSsh;
  String fingerprintSha256;
  bool isEncrypted;
  String? passphrase;
  DateTime createdAt;

  SshKeyEntry({
    required this.id,
    required this.name,
    required this.algorithm,
    this.comment = '',
    required this.publicKeyOpenSsh,
    required this.privateKeyOpenSsh,
    required this.fingerprintSha256,
    this.isEncrypted = false,
    this.passphrase,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'algorithm': algorithm,
        'comment': comment,
        'publicKeyOpenSsh': publicKeyOpenSsh,
        'privateKeyOpenSsh': privateKeyOpenSsh,
        'fingerprintSha256': fingerprintSha256,
        'isEncrypted': isEncrypted,
        'passphrase': passphrase,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SshKeyEntry.fromJson(Map<String, dynamic> json) => SshKeyEntry(
        id: json['id'] as String,
        name: json['name'] as String,
        algorithm: json['algorithm'] as String,
        comment: (json['comment'] as String?) ?? '',
        publicKeyOpenSsh: json['publicKeyOpenSsh'] as String,
        privateKeyOpenSsh: json['privateKeyOpenSsh'] as String,
        fingerprintSha256: json['fingerprintSha256'] as String,
        isEncrypted: (json['isEncrypted'] as bool?) ?? false,
        passphrase: json['passphrase'] as String?,
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'] as String)
            : null,
      );
}
