import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'models/order.dart';
import 'services/firestore_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // Iniciar sesión de forma anónima para cumplir con las reglas de Firestore
    await FirebaseAuth.instance.signInAnonymously();
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

  // Estado de vinculación del reloj
  String? _watchId;
  String? _clientId;
  bool _isLoaded = false;
  StreamSubscription<DocumentSnapshot>? _watchSubscription;

  @override
  void initState() {
    super.initState();
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 10), (_) => _updateClock());
    
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );

    _initPairingState();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _shakeController.dispose();
    _watchSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initPairingState() async {
    final prefs = await SharedPreferences.getInstance();
    String? wId = prefs.getString('watchId');
    String? cId = prefs.getString('clientId');

    if (wId == null) {
      final random = math.Random();
      wId = 'WATCH_${10000 + random.nextInt(90000)}'; // e.g. WATCH_12345
      await prefs.setString('watchId', wId);
    }

    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    await firestoreService.registerWatch(wId);

    if (mounted) {
      setState(() {
        _watchId = wId;
        _clientId = cId;
        _isLoaded = true;
      });
    }

    // Escuchar el estado de vinculación en tiempo real en Firestore
    _watchSubscription = FirebaseFirestore.instance
        .collection('watches')
        .doc(wId)
        .snapshots()
        .listen((snap) async {
      if (snap.exists) {
        final data = snap.data();
        final newClientId = data?['clientId'] as String?;
        
        if (newClientId != _clientId) {
          final prefs = await SharedPreferences.getInstance();
          if (newClientId != null && newClientId.isNotEmpty) {
            await prefs.setString('clientId', newClientId);
          } else {
            await prefs.remove('clientId');
          }
          if (mounted) {
            setState(() {
              _clientId = (newClientId == null || newClientId.isEmpty) ? null : newClientId;
            });
          }
        }
      }
    }, onError: (error) {
      print("Warning: could not listen to watch pairing document in Firestore: $error");
    });
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

  Widget _buildPairingScreen() {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'DELIVECOSYS',
            style: TextStyle(
              color: Color(0xFF3B82F6),
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Vincular Reloj',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: QrImageView(
              data: _watchId ?? '',
              version: QrVersions.auto,
              size: 80.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'ID: $_watchId',
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 8,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final mediaQuery = MediaQuery.of(context);
    final isNativeWatch = mediaQuery.size.width < 500 && mediaQuery.size.height < 500;

    if (!_isLoaded) {
      return const Scaffold(
        backgroundColor: Color(0xFF0F172A),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (isNativeWatch) {
      // Standalone Wear OS UI: Muestra la interfaz circular completa en la pantalla del reloj
      return Scaffold(
        backgroundColor: const Color(0xFF0F172A),
        body: ClipOval(
          child: _clientId == null
              ? _buildPairingScreen()
              : StreamBuilder<List<Order>>(
                  stream: firestoreService.getOrdersStream(_clientId!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    final orders = snapshot.data ?? [];
                    
                    // Buscar primer pedido en tránsito o que haya llegado
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

                    // Hacer vibrar el reloj si el repartidor llega
                    if (activeNotifOrder != null && activeNotifOrder.status != _lastStatus) {
                      if (activeNotifOrder.status == 'arrived') {
                        WidgetsBinding.instance.addPostFrameCallback((_) => _triggerVibration());
                      }
                      _lastStatus = activeNotifOrder.status;
                    }

                    return AnimatedBuilder(
                      animation: _shakeController,
                      builder: (context, child) {
                        final double dx = (0.5 - _shakeController.value).abs() * 10 * (_shakeController.value > 0.5 ? 1 : -1);
                        return Transform.translate(
                          offset: Offset(dx, 0),
                          child: child,
                        );
                      },
                      child: activeNotifOrder == null || activeNotifOrder.status == 'delivered' && _lastStatus == 'delivered'
                          ? _buildClockFace(isDark: true)
                          : _buildNotificationFace(activeNotifOrder, firestoreService, isDark: true),
                    );
                  },
                ),
        ),
      );
    }

    // Vista de Simulador para móvil/escritorio
    return Scaffold(
      backgroundColor: const Color(0xFF0B0F19), // Fondo del panel
      body: Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Correa del Reloj
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
            
            // Cuerpo del Reloj
            Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF1E293B), width: 6),
                boxShadow: const [
                  BoxShadow(color: Colors.black87, blurRadius: 30, offset: Offset(0, 10)),
                ],
              ),
              child: ClipOval(
                child: Scaffold(
                  backgroundColor: _clientId == null ? const Color(0xFF0F172A) : Colors.white,
                  body: _clientId == null
                      ? _buildPairingScreen()
                      : StreamBuilder<List<Order>>(
                          stream: firestoreService.getOrdersStream(_clientId!),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const Center(child: CircularProgressIndicator());
                            }

                            final orders = snapshot.data ?? [];
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
                                  ? _buildClockFace(isDark: false)
                                  : _buildNotificationFace(activeNotifOrder, firestoreService, isDark: false),
                            );
                          },
                        ),
                ),
              ),
            ),
            
            // Botón Corona del Reloj
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

  Widget _buildClockFace({required bool isDark}) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final dateColor = isDark ? const Color(0xFF60A5FA) : const Color(0xFF2563EB);
    final iconBg = isDark ? const Color(0xFF1E293B) : const Color(0xFFF3F4F6);
    final iconBorder = isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB);
    final iconColor = isDark ? Colors.white70 : Colors.grey;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'LUN 22 JUN',
          style: TextStyle(color: dateColor, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        Text(
          _timeStr,
          style: TextStyle(fontSize: 36, fontWeight: FontWeight.w900, letterSpacing: -1, color: textColor),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: iconBg,
                shape: BoxShape.circle,
                border: Border.all(color: iconBorder),
              ),
              child: Icon(Icons.shopping_bag, size: 16, color: iconColor),
            )
          ],
        )
      ],
    );
  }

  Widget _buildNotificationFace(Order order, FirestoreService service, {required bool isDark}) {
    final bgColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.white60 : Colors.grey;
    final buttonTextColor = isDark ? Colors.white : Colors.black87;
    final buttonBorderColor = isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB);

    if (order.status == 'delivered') {
      Future.delayed(const Duration(seconds: 3), () {
        setState(() {
          _lastStatus = null;
        });
      });

      return Container(
        color: bgColor,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 48),
            const SizedBox(height: 8),
            Text(
              '¡Entregado!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? const Color(0xFF34D399) : const Color(0xFF065F46)),
            ),
            Text('Gracias por comprar', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
          ],
        ),
      );
    }

    return Container(
      color: bgColor,
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
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: textColor),
          ),
          
          if (order.status == 'arrived') ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: isDark ? Colors.black38 : Colors.black,
                border: isDark ? Border.all(color: const Color(0xFF334155)) : null,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _PulsingWatchDot(),
                const SizedBox(width: 4),
                Text('Esperando validación...', style: TextStyle(fontSize: 9, color: secondaryTextColor)),
              ],
            )
          ],
          
          if (order.status == 'in_transit') ...[
            const SizedBox(height: 6),
            Text('Cliente: ${order.client}', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
            const SizedBox(height: 8),
            SizedBox(
              height: 28,
              child: OutlinedButton(
                onPressed: () {
                  service.addChatMessage(order.id, 'client', '¡Ya voy bajando! Espérame en la entrada, por favor.');
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  side: BorderSide(color: buttonBorderColor),
                ),
                child: Text('¡Ya voy! 🏃', style: TextStyle(fontSize: 10, color: buttonTextColor)),
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
