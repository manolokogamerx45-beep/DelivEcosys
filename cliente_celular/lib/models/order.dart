class Order {
  final String id;
  final String item;
  final String client;
  final String brand;
  final String status; // pending, accepted, in_transit, arrived, delivered
  final String driverId;
  final String driverName;
  final String driverVehicle;
  final String passcode;
  final double progress;
  final int eta;
  final double currentX; // Para compatibilidad, o latitud actual
  final double currentY; // Para compatibilidad, o longitud actual
  final double destLatitude;
  final double destLongitude;
  final List<Map<String, dynamic>> chatLogs;

  Order({
    required this.id,
    required this.item,
    required this.client,
    required this.brand,
    required this.status,
    this.driverId = '',
    required this.driverName,
    required this.driverVehicle,
    required this.passcode,
    required this.progress,
    required this.eta,
    required this.currentX,
    required this.currentY,
    required this.destLatitude,
    required this.destLongitude,
    required this.chatLogs,
  });

  factory Order.fromMap(String documentId, Map<String, dynamic> data) {
    return Order(
      id: documentId,
      item: data['item'] ?? '',
      client: data['client'] ?? '',
      brand: data['brand'] ?? '',
      status: data['status'] ?? 'pending',
      driverId: data['driverId'] ?? '',
      driverName: data['driverName'] ?? '',
      driverVehicle: data['driverVehicle'] ?? '',
      passcode: data['passcode'] ?? '',
      progress: (data['progress'] ?? 0.0).toDouble(),
      eta: data['eta'] ?? 0,
      currentX: (data['currentX'] ?? 0.0).toDouble(),
      currentY: (data['currentY'] ?? 0.0).toDouble(),
      destLatitude: (data['destLatitude'] ?? 20.3700).toDouble(),
      destLongitude: (data['destLongitude'] ?? -100.0150).toDouble(),
      chatLogs: List<Map<String, dynamic>>.from(data['chatLogs'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'item': item,
      'client': client,
      'brand': brand,
      'status': status,
      'driverId': driverId,
      'driverName': driverName,
      'driverVehicle': driverVehicle,
      'passcode': passcode,
      'progress': progress,
      'eta': eta,
      'currentX': currentX,
      'currentY': currentY,
      'destLatitude': destLatitude,
      'destLongitude': destLongitude,
      'chatLogs': chatLogs,
    };
  }
}
