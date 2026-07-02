class Order {
  final String id;
  final String item;
  final String client;
  final String clientId;        // uid de Firebase del dueño del paquete
  final String trackingNumber;  // Código de barras / número de rastreo
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
  final bool driverArchived; // Si el repartidor archivó/ocultó el paquete entregado
  final bool clientArchived; // Si el cliente archivó/ocultó el paquete entregado

  Order({
    required this.id,
    required this.item,
    required this.client,
    this.clientId = '',
    this.trackingNumber = '',
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
    this.driverArchived = false,
    this.clientArchived = false,
  });

  factory Order.fromMap(String documentId, Map<String, dynamic> data) {
    return Order(
      id: documentId,
      item: data['item'] ?? '',
      client: data['client'] ?? '',
      clientId: data['clientId'] ?? '',
      trackingNumber: data['trackingNumber'] ?? '',
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
      driverArchived: data['driverArchived'] ?? false,
      clientArchived: data['clientArchived'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'item': item,
      'client': client,
      'clientId': clientId,
      'trackingNumber': trackingNumber,
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
      'driverArchived': driverArchived,
      'clientArchived': clientArchived,
    };
  }
}
