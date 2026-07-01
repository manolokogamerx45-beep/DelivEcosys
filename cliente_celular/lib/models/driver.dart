class Driver {
  final String uid;
  final String name;
  final String email;
  final String phone;
  final String vehicle;
  final String plate;
  final String status; // 'available' | 'busy' | 'offline'
  final bool active;
  final int createdAt;
  final String photoUrl; // Foto de perfil opcional

  const Driver({
    required this.uid,
    required this.name,
    required this.email,
    required this.phone,
    required this.vehicle,
    required this.plate,
    this.status = 'offline',
    this.active = true,
    required this.createdAt,
    this.photoUrl = '',
  });

  factory Driver.fromMap(String uid, Map<String, dynamic> data) {
    return Driver(
      uid: uid,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      phone: data['phone'] ?? '',
      vehicle: data['vehicle'] ?? '',
      plate: data['plate'] ?? '',
      status: data['status'] ?? 'offline',
      active: data['active'] ?? true,
      createdAt: data['createdAt'] ?? 0,
      photoUrl: data['photoUrl'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'email': email,
      'phone': phone,
      'vehicle': vehicle,
      'plate': plate,
      'status': status,
      'active': active,
      'createdAt': createdAt,
      'photoUrl': photoUrl,
    };
  }

  String get statusLabel {
    switch (status) {
      case 'available': return 'Disponible';
      case 'busy': return 'En entrega';
      case 'offline': return 'Desconectado';
      default: return status;
    }
  }
}
