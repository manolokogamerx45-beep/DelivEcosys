import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import '../models/order.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Stream of orders for a specific client in real-time
  Stream<List<Order>> getOrdersStream(String clientId) {
    return _db
        .collection('orders')
        .where('clientId', isEqualTo: clientId)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => Order.fromMap(doc.id, doc.data())).toList();
    });
  }

  // Register watch in Firestore if it doesn't exist
  Future<void> registerWatch(String watchId) async {
    try {
      final docRef = _db.collection('watches').doc(watchId);
      final snap = await docRef.get();
      if (!snap.exists) {
        await docRef.set({
          'clientId': '',
          'status': 'unpaired',
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      print("Warning: could not register watch $watchId in Firestore. Rules might be blocking access: $e");
    }
  }

  // Add chat message from smartwatch quick action
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
}
