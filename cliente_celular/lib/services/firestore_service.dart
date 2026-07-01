import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import '../models/order.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stream of all orders in real-time
  Stream<List<Order>> getOrdersStream() {
    return _db.collection('orders').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => Order.fromMap(doc.id, doc.data())).toList();
    });
  }

  // Update order status
  Future<void> updateOrderStatus(String orderId, String status) async {
    await _db.collection('orders').doc(orderId).update({
      'status': status,
    });
  }

  // Assign driver to order
  Future<void> assignDriverToOrder(
    String orderId, {
    required String driverId,
    required String driverName,
    required String driverVehicle,
  }) async {
    await _db.collection('orders').doc(orderId).update({
      'driverId': driverId,
      'driverName': driverName,
      'driverVehicle': driverVehicle,
      'status': 'accepted',
    });
  }

  // Update order tracking parameters
  Future<void> updateOrderTracking(
    String orderId, {
    required double currentX,
    required double currentY,
    required double progress,
    required int eta,
  }) async {
    await _db.collection('orders').doc(orderId).update({
      'currentX': currentX,
      'currentY': currentY,
      'progress': progress,
      'eta': eta,
    });
  }

  // Add chat message (works for both client and driver roles)
  Future<void> addChatMessage(String orderId, String sender, String text) async {
    final docRef = _db.collection('orders').doc(orderId);
    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (snapshot.exists) {
        final currentLogs = List<Map<String, dynamic>>.from(snapshot.data()?['chatLogs'] ?? []);
        currentLogs.add({
          'sender': sender,
          'text': text,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        });
        transaction.update(docRef, {'chatLogs': currentLogs});
      }
    });
  }

  // Reset/Seed initial orders data
  Future<void> seedInitialOrders() async {
    final initialData = {
      'order-1': {
        'item': 'Audífonos Over-Ear',
        'client': 'Emmanuel S.',
        'brand': 'Amazon Prime',
        'status': 'pending',
        'driverId': '',
        'driverName': '',
        'driverVehicle': '',
        'passcode': '4829',
        'progress': 0.0,
        'eta': 8,
        'currentX': 20.3720,
        'currentY': -100.0190,
        'destLatitude': 20.3680,
        'destLongitude': -100.0120,
        'chatLogs': [
          {'sender': 'system', 'text': 'Pedido creado en Amazon Prime', 'timestamp': DateTime.now().millisecondsSinceEpoch}
        ]
      },
      'order-2': {
        'item': 'Teclado Mecánico',
        'client': 'Sofía L.',
        'brand': 'MercadoLibre',
        'status': 'pending',
        'driverId': '',
        'driverName': '',
        'driverVehicle': '',
        'passcode': '7721',
        'progress': 0.0,
        'eta': 12,
        'currentX': 20.3720,
        'currentY': -100.0190,
        'destLatitude': 20.3750,
        'destLongitude': -100.0150,
        'chatLogs': [
          {'sender': 'system', 'text': 'Pedido creado en MercadoLibre', 'timestamp': DateTime.now().millisecondsSinceEpoch}
        ]
      },
      'order-3': {
        'item': 'Smartphone',
        'client': 'Roberto M.',
        'brand': 'DHL Express',
        'status': 'pending',
        'driverId': '',
        'driverName': '',
        'driverVehicle': '',
        'passcode': '9083',
        'progress': 0.0,
        'eta': 6,
        'currentX': 20.3720,
        'currentY': -100.0190,
        'destLatitude': 20.3700,
        'destLongitude': -100.0250,
        'chatLogs': [
          {'sender': 'system', 'text': 'Pedido creado en DHL Express', 'timestamp': DateTime.now().millisecondsSinceEpoch}
        ]
      }
    };

    final batch = _db.batch();
    initialData.forEach((key, value) {
      final docRef = _db.collection('orders').doc(key);
      batch.set(docRef, value, SetOptions(merge: true));
    });
    await batch.commit();
  }
}
