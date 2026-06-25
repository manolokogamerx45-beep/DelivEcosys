import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'models/order.dart';
import 'services/firestore_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint("Firebase connection failed: $e");
  }

  runApp(
    Provider<FirestoreService>(
      create: (_) => FirestoreService(),
      child: const WatchApp(),
    ),
  );
}

class WatchApp extends StatelessWidget {
  const WatchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DelivEcosys - Smartwatch',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFF59E0B),
          background: Colors.black,
        ),
      ),
      home: const WatchFrame(),
    );
  }
}

class WatchFrame extends StatefulWidget {
  const WatchFrame({super.key});

  @override
  State<WatchFrame> createState() => _WatchFrameState();
}

class _WatchFrameState extends State<WatchFrame> with SingleTickerProviderStateMixin {
  String _timeStr = '18:02';
  Timer? _clockTimer;
  late AnimationController _shakeController;
  String? _lastStatus;

  @override
  void initState() {
    super.initState();
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 10), (_) => _updateClock());
    
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _shakeController.dispose();
    super.dispose();
  }

  void _updateClock() {
    final now = DateTime.now();
    setState(() {
      _timeStr = "${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}";
    });
  }

  void _triggerVibration() {
    _shakeController.forward(from: 0.0).then((_) {
      _shakeController.reverse().then((_) {
        _shakeController.forward(from: 0.0).then((_) {
          _shakeController.reverse();
        });
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19), // Dark dashboard context
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Smartwatch Strap
            Container(
              width: 54,
              height: 380,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF334155), Color(0xFF1E293B)],
                ),
              ),
            ),
            
            // Smartwatch Frame Body
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF1E293B), width: 6),
                boxShadow: const [
                  BoxShadow(color: Colors.black84, blurRadius: 30, offset: Offset(0, 10)),
                ],
              ),
              child: ClipOval(
                child: Scaffold(
                  backgroundColor: Colors.white,
                  body: StreamBuilder<List<Order>>(
                    stream: firestoreService.getOrdersStream(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final orders = snapshot.data ?? [];
                      
                      // Find first active notification order (Amazon default or first active)
                      Order? activeNotifOrder;
                      try {
                        activeNotifOrder = orders.firstWhere((o) => o.status == 'in_transit' || o.status == 'arrived');
                      } catch (_) {
                        try {
                          activeNotifOrder = orders.firstWhere((o) => o.status == 'delivered');
                        } catch (_) {
                          activeNotifOrder = null;
                        }
                      }

                      // Shake watch if status changes to arrived
                      if (activeNotifOrder != null && activeNotifOrder.status != _lastStatus) {
                        if (activeNotifOrder.status == 'arrived') {
                          WidgetsBinding.instance.addPostFrameCallback((_) => _triggerVibration());
                        }
                        _lastStatus = activeNotifOrder.status;
                      }

                      return AnimatedBuilder(
                        animation: _shakeController,
                        builder: (context, child) {
                          final double dx = (0.5 - _shakeController.value).abs() * 10 * ( _shakeController.value > 0.5 ? 1 : -1);
                          return Transform.translate(
                            offset: Offset(dx, 0),
                            child: child,
                          );
                        },
                        child: activeNotifOrder == null || activeNotifOrder.status == 'delivered' && _lastStatus == 'delivered'
                            ? _buildClockFace()
                            : _buildNotificationFace(activeNotifOrder, firestoreService),
                      );
                    },
                  ),
                ),
              ),
            ),
            
            // Watch Crown Button
            Positioned(
              right: 18,
              child: Container(
                width: 6,
                height: 22,
                decoration: BoxDecoration(
                  color: const Color(0xFF334155),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClockFace() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          'LUN 22 JUN',
          style: TextStyle(color: Color(0xFF2563EB), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        Text(
          _timeStr,
          style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1, color: Colors.black87),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: const Icon(Icons.shopping_bag, size: 16, color: Colors.grey),
            )
          ],
        )
      ],
    );
  }

  Widget _buildNotificationFace(Order order, FirestoreService service) {
    if (order.status == 'delivered') {
      // Temporary delivery success face
      Future.delayed(const Duration(seconds: 3), () {
        setState(() {
          _lastStatus = null;
        });
      });

      return Container(
        color: Colors.white,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Color(0xFF10B981), size: 48),
            SizedBox(height: 8),
            Text(
              '¡Entregado!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF065F46)),
            ),
            Text('Gracias por comprar', style: TextStyle(fontSize: 10, color: Colors.grey)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_getBrandIcon(order.brand), style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
              Text(
                order.brand.toUpperCase(),
                style: TextStyle(fontWeight: FontWeight.bold, color: _getBrandColor(order.brand), fontSize: 10, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            order.status == 'in_transit' ? 'Paquete en camino' : '¡Repartidor afuera!',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
          ),
          
          if (order.status == 'arrived') ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  const Text('CLAVE DE ENTREGA', style: TextStyle(color: Colors.white54, fontSize: 7, fontWeight: FontWeight.bold)),
                  Text(
                    order.passcode,
                    style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 18, letterSpacing: 2),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PulsingWatchDot(),
                SizedBox(width: 4),
                Text('Esperando validación...', style: TextStyle(fontSize: 9, color: Colors.grey)),
              ],
            )
          ],
          
          if (order.status == 'in_transit') ...[
            const SizedBox(height: 6),
            Text('Cliente: ${order.client}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 8),
            SizedBox(
              height: 28,
              child: OutlinedButton(
                onPressed: () {
                  service.addChatMessage(order.id, 'client', '¡Ya voy bajando! Espérame en la entrada, por favor.');
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: const BorderSide(color: Color(0xFFE5E7EB)),
                ),
                child: const Text('¡Ya voy! 🏃', style: TextStyle(fontSize: 10, color: Colors.black87)),
              ),
            )
          ]
        ],
      ),
    );
  }

  Color _getBrandColor(String brand) {
    if (brand.contains('Amazon')) return const Color(0xFFFF9900);
    if (brand.contains('MercadoLibre')) return const Color(0xFF2563EB);
    if (brand.contains('DHL')) return const Color(0xFFCC0000);
    return Colors.blue;
  }

  String _getBrandIcon(String brand) {
    if (brand.contains('Amazon')) return '📦';
    if (brand.contains('MercadoLibre')) return '💛';
    return '📦';
  }
}

class _PulsingWatchDot extends StatefulWidget {
  const _PulsingWatchDot();

  @override
  State<_PulsingWatchDot> createState() => _PulsingWatchDotState();
}

class _PulsingWatchDotState extends State<_PulsingWatchDot> with SingleTickerProviderStateMixin {
  late AnimationController _pulsingController;

  @override
  void initState() {
    super.initState();
    _pulsingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulsingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.3, end: 1.0).animate(_pulsingController),
      child: Container(
        width: 6,
        height: 6,
        decoration: const BoxDecoration(
          color: Colors.amber,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
