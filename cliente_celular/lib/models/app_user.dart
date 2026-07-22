class AppUser {
  final String uid;
  final String email;
  final String name;
  final String role; // 'admin' | 'driver' | 'client'

  const AppUser({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
  });

  factory AppUser.fromMap(String uid, Map<String, dynamic> data) {
    return AppUser(
      uid: uid,
      email: data['email'] ?? '',
      name: data['name'] ?? '',
      role: data['role'] ?? 'client',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'name': name,
      'role': role,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
  }

  bool get isAdmin => role == 'admin';
  bool get isDriver => role == 'driver';
  bool get isClient => role == 'client';
}
