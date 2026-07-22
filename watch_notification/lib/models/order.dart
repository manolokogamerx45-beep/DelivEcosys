class Order {
  final String id;
  final String item;
  final String client;
  final String brand;
  final String status; // pending, accepted, in_transit, arrived, delivered
  final String driverName;
  final String driverVehicle;
  final String passcode;
  final double progress;
  final int eta;
  final double currentX;
  final double currentY;
  final List<Map<String, dynamic>> chatLogs;

  Order({
    required this.id,
    required this.item,
    required this.client,
    required this.brand,
    required this.status,
    required this.driverName,
    required this.driverVehicle,
    required this.passcode,
    required this.progress,
    required this.eta,
    required this.currentX,
    required this.currentY,
    required this.chatLogs,
  });

  factory Order.fromMap(String documentId, Map<String, dynamic> data) {
    return Order(
      id: documentId,
      item: data['item'] ?? '',
      client: data['client'] ?? '',
      brand: data['brand'] ?? '',
      status: data['status'] ?? 'pending',
      driverName: data['driverName'] ?? '',
      driverVehicle: data['driverVehicle'] ?? '',
      passcode: data['passcode'] ?? '',
      progress: (data['progress'] ?? 0.0).toDouble(),
      eta: data['eta'] ?? 0,
      currentX: (data['currentX'] ?? 0.0).toDouble(),
      currentY: (data['currentY'] ?? 0.0).toDouble(),
      chatLogs: List<Map<String, dynamic>>.from(data['chatLogs'] ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'item': item,
      'client': client,
      'brand': brand,
      'status': status,
      'driverName': driverName,
      'driverVehicle': driverVehicle,
      'passcode': passcode,
      'progress': progress,
      'eta': eta,
      'currentX': currentX,
      'currentY': currentY,
      'chatLogs': chatLogs,
    };
  }
}
