import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'models/order.dart';
import 'services/firestore_service.dart';
import 'widgets/vector_map_painter.dart';

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
      child: const UnifiedDelivApp(),
    ),
  );
}

class UnifiedDelivApp extends StatelessWidget {
  const UnifiedDelivApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DelivEcosys - App Unificada',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF9FAFB),
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF3B82F6),
          brightness: Brightness.light,
          background: const Color(0xFFF9FAFB),
        ),
      ),
      home: const AuthWrapper(),
    );
  }
}

// ----------------------------------------------------------------------------
// Authentication Wrapper / Role Switcher State
// ----------------------------------------------------------------------------
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoggedIn = false;
  String _role = 'client'; // 'client' or 'driver'
  String _selectedOrderId = 'order-1'; // Tracks active client view order selection

  void _login(String role, String selectedOrderId) {
    setState(() {
      _role = role;
      _selectedOrderId = selectedOrderId;
      _isLoggedIn = true;
    });
  }

  void _logout() {
    setState(() {
      _isLoggedIn = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isLoggedIn) {
      return LoginScreen(onLogin: _login);
    }

    if (_role == 'driver') {
      return RiderDashboardScreen(onLogout: _logout);
    }

    return CustomerPhoneScreen(
      selectedOrderId: _selectedOrderId,
      onLogout: _logout,
    );
  }
}

// ----------------------------------------------------------------------------
// Login Screen Layout
// ----------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  final Function(String role, String selectedOrderId) onLogin;

  const LoginScreen({super.key, required this.onLogin});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _emailController = TextEditingController(text: 'emmanuel@cliente.com');
  final _passwordController = TextEditingController(text: '123456');
  final _driverController = TextEditingController(text: 'carlos@repartidor.com');
  final _driverPasswordController = TextEditingController(text: 'driver123');
  String _selectedClientOrderId = 'order-1';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _driverController.dispose();
    _driverPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFEFF6FF), // Soft premium blue-grey background
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Logo/Header Icon
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFF3B82F6),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(color: Colors.blueAccent, blurRadius: 15, offset: Offset(0, 4)),
                  ],
                ),
                child: const Icon(Icons.local_shipping, color: Colors.white, size: 32),
              ),
              const SizedBox(height: 16),
              const Text(
                'DelivEcosys',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 24, letterSpacing: 0.5, color: Color(0xFF1E3A8A)),
              ),
              const Text(
                'Sistema Unificado de Reparto',
                style: TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 32),
              
              // Auth Card
              Card(
                color: Colors.white,
                elevation: 8,
                shadowColor: Colors.black12,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                child: Container(
                  width: 380,
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      // Role Selector Tabs
                      TabBar(
                        controller: _tabController,
                        labelColor: const Color(0xFF3B82F6),
                        unselectedLabelColor: Colors.black45,
                        indicatorColor: const Color(0xFF3B82F6),
                        indicatorSize: TabBarIndicatorSize.tab,
                        tabs: const [
                          Tab(icon: Icon(Icons.person), text: 'Cliente'),
                          Tab(icon: Icon(Icons.delivery_dining), text: 'Repartidor'),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Tab contents wrapper
                      SizedBox(
                        height: 270,
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            // 1. Client Login Form
                            _buildClientTab(),
                            // 2. Driver Login Form
                            _buildDriverTab(),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildClientTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('SELECCIONA TU PERFIL DE CLIENTE:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedClientOrderId,
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            fillColor: const Color(0xFFF3F4F6),
            filled: true,
          ),
          items: const [
            DropdownMenuItem(value: 'order-1', child: Text('Emmanuel S. (Amazon)')),
            DropdownMenuItem(value: 'order-2', child: Text('Sofía L. (MercadoLibre)')),
            DropdownMenuItem(value: 'order-3', child: Text('Roberto M. (DHL Express)')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedClientOrderId = val;
                if (val == 'order-1') _emailController.text = 'emmanuel@cliente.com';
                if (val == 'order-2') _emailController.text = 'sofia@cliente.com';
                if (val == 'order-3') _emailController.text = 'roberto@cliente.com';
              });
            }
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _emailController,
          decoration: InputDecoration(
            labelText: 'Correo Electrónico',
            prefixIcon: const Icon(Icons.email_outlined, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: () => widget.onLogin('client', _selectedClientOrderId),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF3B82F6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Iniciar Sesión Cliente', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        )
      ],
    );
  }

  Widget _buildDriverTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('CREDENCIALES DE ACCESO ESPECIAL:', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
        const SizedBox(height: 12),
        TextField(
          controller: _driverController,
          decoration: InputDecoration(
            labelText: 'Código / Correo del Repartidor',
            prefixIcon: const Icon(Icons.badge_outlined, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _driverPasswordController,
          obscureText: true,
          decoration: InputDecoration(
            labelText: 'Contraseña',
            prefixIcon: const Icon(Icons.lock_outline, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: () => widget.onLogin('driver', ''),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981), // Driver Emerald Green
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Iniciar Sesión Repartidor', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        )
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Customer Phone Tracking Screen
// ----------------------------------------------------------------------------
class CustomerPhoneScreen extends StatefulWidget {
  final String selectedOrderId;
  final VoidCallback onLogout;

  const CustomerPhoneScreen({
    super.key, 
    required this.selectedOrderId, 
    required this.onLogout
  });

  @override
  State<CustomerPhoneScreen> createState() => _CustomerPhoneScreenState();
}

class _CustomerPhoneScreenState extends State<CustomerPhoneScreen> {
  late String _selectedOrderId;
  bool _showChat = false;
  final TextEditingController _chatController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedOrderId = widget.selectedOrderId;
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  Order _getFallbackOrder(String id) {
    if (id == 'order-1') {
      return Order(
        id: 'order-1',
        item: 'Audífonos Over-Ear',
        client: 'Emmanuel S.',
        brand: 'Amazon Prime',
        status: 'pending',
        driverName: 'Carlos Ruiz',
        driverVehicle: 'Motocicleta Honda (Negra) - FHJ-429',
        passcode: '4829',
        progress: 0.0,
        eta: 8,
        currentX: 80.0,
        currentY: 70.0,
        chatLogs: [
          {'sender': 'system', 'text': 'Pedido creado en Amazon Prime', 'timestamp': DateTime.now().millisecondsSinceEpoch}
        ],
      );
    } else if (id == 'order-2') {
      return Order(
        id: 'order-2',
        item: 'Teclado Mecánico',
        client: 'Sofía L.',
        brand: 'MercadoLibre',
        status: 'pending',
        driverName: 'Sofía López',
        driverVehicle: 'Yamaha Cripton (Azul) - KLJ-881',
        passcode: '7721',
        progress: 0.0,
        eta: 12,
        currentX: 80.0,
        currentY: 70.0,
        chatLogs: [
          {'sender': 'system', 'text': 'Pedido creado en MercadoLibre', 'timestamp': DateTime.now().millisecondsSinceEpoch}
        ],
      );
    } else {
      return Order(
        id: 'order-3',
        item: 'Smartphone',
        client: 'Roberto M.',
        brand: 'DHL Express',
        status: 'pending',
        driverName: 'Roberto Gómez',
        driverVehicle: 'Nissan Urvan (Blanco) - PLM-341',
        passcode: '9083',
        progress: 0.0,
        eta: 6,
        currentX: 80.0,
        currentY: 70.0,
        chatLogs: [
          {'sender': 'system', 'text': 'Pedido creado en DHL Express', 'timestamp': DateTime.now().millisecondsSinceEpoch}
        ],
      );
    }
  }

  Color _getBrandColor(String brand) {
    if (brand.contains('Amazon')) return const Color(0xFFFF9900);
    if (brand.contains('MercadoLibre')) return const Color(0xFF2563EB);
    if (brand.contains('DHL')) return const Color(0xFFCC0000);
    return Colors.blue;
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      body: SafeArea(
        child: StreamBuilder<List<Order>>(
          stream: firestoreService.getOrdersStream(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final orders = snapshot.data ?? [];
            final bool isLive = snapshot.hasData && orders.any((o) => o.id == _selectedOrderId);
            Order? activeOrder;
            
            try {
              activeOrder = orders.firstWhere((o) => o.id == _selectedOrderId);
            } catch (_) {
              activeOrder = _getFallbackOrder(_selectedOrderId);
            }

            return Stack(
              children: [
                Column(
                  children: [
                    // App Bar Client Switcher & Logout
                    _buildAppHeader(activeOrder, isLive: isLive),

                    if (!isLive)
                      Container(
                        width: double.infinity,
                        color: Colors.amber.shade50,
                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 14, color: Colors.amber.shade900),
                            const SizedBox(width: 6),
                            Text(
                              'Conexión local simulada (Presiona "Reset DB" en Repartidor para activar)',
                              style: TextStyle(color: Colors.amber.shade900, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),

                    // Main tracker body
                    Expanded(
                      child: activeOrder.status == 'pending'
                          ? _buildEmptyState(activeOrder)
                          : _buildTrackingScreen(activeOrder, firestoreService),
                    ),
                  ],
                ),

                // Chat Overlay panel
                if (_showChat)
                  _buildChatOverlay(activeOrder, firestoreService, 'client'),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAppHeader(Order order, {required bool isLive}) {
    return Container(
      height: 56,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CircleAvatar(
            backgroundColor: _getBrandColor(order.brand).withOpacity(0.1),
            radius: 16,
            child: Text(
              _getBrandEmoji(order.brand),
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isLive ? const Color(0xFF10B981) : Colors.amber,
                ),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedOrderId,
                  dropdownColor: Colors.white,
                  icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54, size: 20),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold, 
                    color: Colors.black87, 
                    fontSize: 14,
                    fontFamily: 'Roboto',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'order-1', child: Text('Emmanuel S. (Amazon)')),
                    DropdownMenuItem(value: 'order-2', child: Text('Sofía L. (MercadoLibre)')),
                    DropdownMenuItem(value: 'order-3', child: Text('Roberto M. (DHL)')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedOrderId = val;
                        _showChat = false;
                      });
                    }
                  },
                ),
              ),
            ],
          ),
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout, size: 20, color: Colors.redAccent),
            tooltip: 'Cerrar Sesión',
          )
        ],
      ),
    );
  }

  Widget _buildEmptyState(Order order) {
    final brandColor = _getBrandColor(order.brand);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PulsingRadar(color: brandColor),
          const SizedBox(height: 40),
          Text(
            'Tu paquete de ${order.brand} está en espera',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold, 
              fontSize: 18, 
              color: Colors.black87,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            ),
            child: RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: const TextStyle(fontSize: 13, color: Colors.black54, height: 1.4),
                children: [
                  const TextSpan(text: 'El repartidor aún no acepta el paquete de '),
                  TextSpan(
                    text: order.item, 
                    style: TextStyle(color: brandColor, fontWeight: FontWeight.bold)
                  ),
                  const TextSpan(text: ' para entregar a '),
                  TextSpan(
                    text: order.client, 
                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold)
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: brandColor.withOpacity(0.8),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Esperando aceptación en el panel de repartidor...',
                style: TextStyle(fontSize: 11, color: Colors.black38, fontWeight: FontWeight.w500),
              )
            ],
          )
        ],
      ),
    );
  }

  Widget _buildTrackingScreen(Order order, FirestoreService service) {
    final brandColor = _getBrandColor(order.brand);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Map Container
        Container(
          height: 250,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: VectorMapPainter(activeOrder: order),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE5E7EB)),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: brandColor,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          order.status == 'accepted'
                              ? 'Conductor asignado'
                              : (order.status == 'in_transit' 
                                  ? 'Repartidor en ruta' 
                                  : (order.status == 'arrived' ? 'Llegó a tu ubicación' : 'Paquete entregado')),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: Colors.black87),
                        ),
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Driver details card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: brandColor.withOpacity(0.1),
                child: Icon(Icons.electric_moped, color: brandColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.driverName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87)),
                    const SizedBox(height: 2),
                    Text(
                      order.driverVehicle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: Colors.black45),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {},
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF3F4F6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(Icons.phone, color: brandColor, size: 18),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () => setState(() => _showChat = true),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF3F4F6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: Icon(Icons.chat_bubble_outline, color: brandColor, size: 18),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Progress card
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Código de Orden: #${order.id.split('-').last.toUpperCase()}', style: const TextStyle(fontSize: 9, color: Colors.black45)),
                      const SizedBox(height: 2),
                      Text(
                        _getProgressTitle(order.status), 
                        style: TextStyle(color: brandColor, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Tiempo Estimado', style: TextStyle(fontSize: 9, color: Colors.black45)),
                      const SizedBox(height: 2),
                      Text('${order.eta} min', style: TextStyle(color: brandColor, fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 20),
              
              // Horizontal Stepper Bar
              _buildStepper(order.status, brandColor),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStepper(String status, Color brandColor) {
    double progressWidth = 0.0;
    int activeStep = 0;
    if (status == 'accepted') {
      progressWidth = 0.0;
      activeStep = 0;
    } else if (status == 'in_transit') {
      progressWidth = 0.33;
      activeStep = 1;
    } else if (status == 'arrived') {
      progressWidth = 0.66;
      activeStep = 2;
    } else if (status == 'delivered') {
      progressWidth = 1.0;
      activeStep = 3;
    }

    Widget stepNode(int stepIndex, String title) {
      bool isDone = stepIndex <= activeStep;
      return Column(
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone ? brandColor : const Color(0xFFE5E7EB),
              border: Border.all(
                color: isDone ? Colors.white : const Color(0xFFCBD5E1),
                width: 1.5,
              ),
              boxShadow: isDone 
                  ? [BoxShadow(color: brandColor.withOpacity(0.3), blurRadius: 4, spreadRadius: 1)]
                  : [],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title, 
            style: TextStyle(
              fontSize: 8.5, 
              color: isDone ? Colors.black87 : Colors.black38, 
              fontWeight: isDone ? FontWeight.bold : FontWeight.normal
            )
          ),
        ],
      );
    }

    return Column(
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: 3,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB), 
                borderRadius: BorderRadius.circular(2)
              ),
            ),
            Positioned(
              left: 10,
              right: 10,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progressWidth,
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: brandColor, 
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            stepNode(0, 'Aceptado'),
            stepNode(1, 'En Camino'),
            stepNode(2, 'Llegó'),
            stepNode(3, 'Entregado'),
          ],
        )
      ],
    );
  }

  String _getBrandEmoji(String brand) {
    if (brand.contains('Amazon')) return '📦';
    if (brand.contains('MercadoLibre')) return '💛';
    return '⚡';
  }

  String _getProgressTitle(String status) {
    if (status == 'accepted') return 'Conductor asignado';
    if (status == 'in_transit') return 'Repartidor en camino';
    if (status == 'arrived') return '¡Repartidor afuera!';
    if (status == 'delivered') return '✓ Entregado con éxito';
    return 'Procesando';
  }
}

// ----------------------------------------------------------------------------
// Reusable Chat Overlay Panel (Shared between Client and Driver)
// ----------------------------------------------------------------------------
Widget _buildChatOverlay(Order order, FirestoreService service, String role) {
  final brandColor = _getBrandColorStatic(order.brand);
  final textController = TextEditingController();

  return StatefulBuilder(
    builder: (context, setOverlayState) {
      return Container(
        color: Colors.black45,
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 420,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(color: Colors.black26, blurRadius: 20, spreadRadius: 5),
            ],
          ),
          child: Column(
            children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: Color(0xFFF3F4F6),
                  border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981)),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          role == 'client' ? 'Chat: ${order.driverName}' : 'Chat: ${order.client}', 
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)
                        ),
                      ],
                    ),
                    IconButton(
                      onPressed: () {
                        // Using a simple pop navigator or closed by calling setState in parent
                        // Since this is drawn conditionally in parent, parent manages visibility
                        if (role == 'client') {
                          final pState = context.findAncestorStateOfType<_CustomerPhoneScreenState>();
                          pState?.setState(() => pState._showChat = false);
                        } else {
                          final pState = context.findAncestorStateOfType<_RiderDashboardScreenState>();
                          pState?.setState(() => pState._showChat = false);
                        }
                      },
                      style: IconButton.styleFrom(backgroundColor: Colors.white),
                      icon: const Icon(Icons.close, size: 16, color: Colors.black54),
                    )
                  ],
                ),
              ),
              
              // Messages List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: order.chatLogs.length,
                  itemBuilder: (context, index) {
                    final log = order.chatLogs[index];
                    final isSystem = log['sender'] == 'system';
                    
                    if (isSystem) {
                      return Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            log['text'] ?? '',
                            style: const TextStyle(color: Colors.black38, fontSize: 10, fontStyle: FontStyle.italic),
                          ),
                        ),
                      );
                    }

                    // Checks if sender is me (matches this view role)
                    final isMe = log['sender'] == role;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        constraints: const BoxConstraints(maxWidth: 240),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: isMe ? brandColor : const Color(0xFFF3F4F6),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(12),
                            topRight: const Radius.circular(12),
                            bottomLeft: Radius.circular(isMe ? 12 : 2),
                            bottomRight: Radius.circular(isMe ? 2 : 12),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 3,
                              offset: Offset(0, isMe ? 2 : 1),
                            )
                          ]
                        ),
                        child: Text(
                          log['text'] ?? '',
                          style: TextStyle(
                            color: isMe ? Colors.white : Colors.black87, 
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Input box
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: textController,
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                        decoration: InputDecoration(
                          hintText: 'Enviar mensaje...',
                          hintStyle: const TextStyle(color: Colors.black38, fontSize: 13),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          filled: true,
                          fillColor: const Color(0xFFF3F4F6),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      onPressed: () {
                        if (textController.text.trim().isNotEmpty) {
                          service.addChatMessage(order.id, role, textController.text.trim());
                          textController.clear();
                        }
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: brandColor,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.send, color: Colors.white, size: 18),
                    )
                  ],
                ),
              )
            ],
          ),
        ),
      );
    },
  );
}

Color _getBrandColorStatic(String brand) {
  if (brand.contains('Amazon')) return const Color(0xFFFF9900);
  if (brand.contains('MercadoLibre')) return const Color(0xFF2563EB);
  if (brand.contains('DHL')) return const Color(0xFFCC0000);
  return Colors.blue;
}

// ----------------------------------------------------------------------------
// Custom Pulsing Radar Widget (Light Theme adapted)
// ----------------------------------------------------------------------------
class PulsingRadar extends StatefulWidget {
  final Color color;
  const PulsingRadar({super.key, required this.color});

  @override
  State<PulsingRadar> createState() => _PulsingRadarState();
}

class _PulsingRadarState extends State<PulsingRadar> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 110 * (1.0 + 0.45 * value),
              height: 110 * (1.0 + 0.45 * value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.color.withOpacity((1.0 - value).clamp(0.0, 1.0)),
                  width: 2,
                ),
              ),
            ),
            Container(
              width: 75 * (1.0 + 0.3 * value),
              height: 75 * (1.0 + 0.3 * value),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: widget.color.withOpacity((0.5 * (1.0 - value)).clamp(0.0, 1.0)),
                  width: 1.5,
                ),
              ),
            ),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    widget.color.withOpacity(0.3),
                    widget.color.withOpacity(0.05),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.color.withOpacity(0.15),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(
                Icons.local_shipping_outlined,
                size: 26,
                color: widget.color,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ----------------------------------------------------------------------------
// Rider Dashboard Screen (Adapted for responsive layout and chat sync)
// ----------------------------------------------------------------------------
class RiderDashboardScreen extends StatefulWidget {
  final VoidCallback onLogout;

  const RiderDashboardScreen({super.key, required this.onLogout});

  @override
  State<RiderDashboardScreen> createState() => _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends State<RiderDashboardScreen> {
  String? _selectedOrderId;
  final Map<String, Timer> _routeTimers = {};
  final Map<String, int> _routeSteps = {};
  final TextEditingController _codeController = TextEditingController();
  bool _codeError = false;
  bool _showChat = false; // Chat Overlay status

  final Map<String, List<Map<String, double>>> _routes = {
    'order-1': [
      {'x': 80.0, 'y': 70.0},
      {'x': 180.0, 'y': 70.0},
      {'x': 180.0, 'y': 170.0},
      {'x': 300.0, 'y': 170.0},
      {'x': 300.0, 'y': 260.0},
      {'x': 420.0, 'y': 260.0},
      {'x': 420.0, 'y': 310.0}
    ],
    'order-2': [
      {'x': 80.0, 'y': 70.0},
      {'x': 180.0, 'y': 70.0},
      {'x': 180.0, 'y': 170.0},
      {'x': 300.0, 'y': 170.0},
      {'x': 300.0, 'y': 340.0}
    ],
    'order-3': [
      {'x': 80.0, 'y': 70.0},
      {'x': 180.0, 'y': 70.0},
      {'x': 180.0, 'y': 170.0},
      {'x': 420.0, 'y': 170.0}
    ]
  };

  @override
  void dispose() {
    for (var timer in _routeTimers.values) {
      timer.cancel();
    }
    _routeTimers.clear();
    _codeController.dispose();
    super.dispose();
  }

  void _startGPSRoute(Order order, FirestoreService service) {
    if (_routeTimers[order.id]?.isActive == true) return;
    
    _routeSteps[order.id] = 0;
    
    service.updateOrderStatus(order.id, 'in_transit');

    final pathPoints = _routes[order.id] ?? [];
    if (pathPoints.isEmpty) return;

    const int totalSteps = 45;
    _routeTimers[order.id] = Timer.periodic(const Duration(milliseconds: 400), (timer) async {
      int currentStep = _routeSteps[order.id] ?? 0;
      if (currentStep >= totalSteps) {
        timer.cancel();
        _routeTimers.remove(order.id);
        _routeSteps.remove(order.id);
        service.updateOrderStatus(order.id, 'arrived');
        service.updateOrderTracking(
          order.id,
          currentX: pathPoints.last['x']!,
          currentY: pathPoints.last['y']!,
          progress: 100.0,
          eta: 0,
        );
        return;
      }

      currentStep++;
      _routeSteps[order.id] = currentStep;
      
      final double progressPercent = (currentStep / totalSteps);
      final int segmentCount = pathPoints.length - 1;
      final double exactSegment = progressPercent * segmentCount;
      final int currentSegmentIdx = exactSegment.floor();
      final double t = exactSegment - currentSegmentIdx;

      if (currentSegmentIdx >= segmentCount) return;

      final pStart = pathPoints[currentSegmentIdx];
      final pEnd = pathPoints[currentSegmentIdx + 1];

      final double rx = pStart['x']! + (pEnd['x']! - pStart['x']!) * t;
      final double ry = pStart['y']! + (pEnd['y']! - pStart['y']!) * t;
      
      final int remainingMinutes = ((1.0 - progressPercent) * 8).round() + 1;

      service.updateOrderTracking(
        order.id,
        currentX: rx,
        currentY: ry,
        progress: progressPercent * 100.0,
        eta: remainingMinutes,
      );
    });
  }

  Color _getBrandColor(String brand) {
    if (brand.contains('Amazon')) return const Color(0xFFFF9900);
    if (brand.contains('MercadoLibre')) return const Color(0xFF2563EB);
    if (brand.contains('DHL')) return const Color(0xFFCC0000);
    return Colors.blue;
  }

  Color _getStatusBg(String status) {
    if (status == 'pending') return const Color(0xFFFEF3C7);
    if (status == 'delivered') return const Color(0xFFD1FAE5);
    return const Color(0xFFDBEAFE);
  }

  Color _getStatusText(String status) {
    if (status == 'pending') return const Color(0xFFD97706);
    if (status == 'delivered') return const Color(0xFF065F46);
    return const Color(0xFF1D4ED8);
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '📍 DelivEcosys',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Color(0xFF10B981)),
              ),
              SizedBox(width: 8),
              Card(
                color: Color(0xFFD1FAE5),
                elevation: 0,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Text('Repartidor', style: TextStyle(color: Color(0xFF065F46), fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              )
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => firestoreService.seedInitialOrders(),
            icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF065F46)),
            label: const Text('Reset DB', style: TextStyle(color: Color(0xFF065F46), fontSize: 12, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
            tooltip: 'Cerrar Sesión',
          )
        ],
      ),
      body: StreamBuilder<List<Order>>(
        stream: firestoreService.getOrdersStream(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final orders = snapshot.data ?? [];
          final activeRoutes = orders.where((o) => o.status != 'pending' && o.status != 'delivered').toList();

          if (activeRoutes.isNotEmpty) {
            if (_selectedOrderId == null || !activeRoutes.any((o) => o.id == _selectedOrderId)) {
              _selectedOrderId = activeRoutes.first.id;
            }
          } else {
            _selectedOrderId = null;
          }
          
          Order? selectedOrder;
          if (_selectedOrderId != null) {
            try {
              selectedOrder = orders.firstWhere((o) => o.id == _selectedOrderId);
            } catch (_) {
              selectedOrder = null;
            }
          }

          // Responsive Layout Builder
          return LayoutBuilder(
            builder: (context, constraints) {
              bool isTablet = constraints.maxWidth >= 600;

              if (isTablet) {
                // Side-by-side tablet layout
                return Stack(
                  children: [
                    Row(
                      children: [
                        // Left sidebar: orders and operations
                        SizedBox(
                          width: 320,
                          child: _buildSidebar(orders, activeRoutes, selectedOrder, firestoreService),
                        ),
                        // Right map view
                        Expanded(
                          child: _buildMapArea(orders, selectedOrder),
                        ),
                      ],
                    ),
                    if (_showChat && selectedOrder != null)
                      _buildChatOverlay(selectedOrder, firestoreService, 'driver'),
                  ],
                );
              } else {
                // Tabbed mobile layout
                return DefaultTabController(
                  length: 2,
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          const TabBar(
                            labelColor: Color(0xFF10B981),
                            unselectedLabelColor: Colors.black45,
                            indicatorColor: Color(0xFF10B981),
                            tabs: [
                              Tab(icon: Icon(Icons.list_alt), text: 'Pedidos'),
                              Tab(icon: Icon(Icons.navigation_outlined), text: 'Navegación'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _buildSidebar(orders, activeRoutes, selectedOrder, firestoreService, fullWidth: true),
                                _buildMapArea(orders, selectedOrder),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (_showChat && selectedOrder != null)
                        _buildChatOverlay(selectedOrder, firestoreService, 'driver'),
                    ],
                  ),
                );
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildSidebar(
    List<Order> orders, 
    List<Order> activeRoutes, 
    Order? selectedOrder, 
    FirestoreService firestoreService,
    {bool fullWidth = false}
  ) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            color: const Color(0xFFF3F4F6),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text(
              'LISTADO DE PEDIDOS',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.grey),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12.0),
              itemCount: orders.length,
              itemBuilder: (context, index) {
                final order = orders[index];
                final isAccepted = order.status != 'pending';
                
                return Card(
                  margin: const EdgeInsets.only(bottom: 12.0),
                  color: order.status == 'delivered' ? const Color(0xFFF3F4F6) : Colors.white,
                  surfaceTintColor: Colors.white,
                  elevation: 2,
                  shadowColor: Colors.black12,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isAccepted ? const Color(0xFF10B981).withOpacity(0.4) : const Color(0xFFE5E7EB),
                      width: 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              order.brand,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: _getBrandColor(order.brand),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _getStatusBg(order.status),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_routeTimers.containsKey(order.id))
                                    Padding(
                                      padding: const EdgeInsets.only(right: 4.0),
                                      child: SizedBox(
                                        width: 8,
                                        height: 8,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          valueColor: AlwaysStoppedAnimation<Color>(_getStatusText(order.status)),
                                        ),
                                      ),
                                    ),
                                  Text(
                                    order.status == 'pending' ? 'DISPONIBLE' : order.status.toUpperCase(),
                                    style: TextStyle(color: _getStatusText(order.status), fontSize: 9, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            )
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Pedido: #${order.id.split('-').last.toUpperCase()}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4),
                        Text('📦 Producto: ${order.item}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                        Text('👤 Cliente: ${order.client}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                        const SizedBox(height: 10),
                        if (order.status == 'pending')
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () => firestoreService.updateOrderStatus(order.id, 'accepted'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Aceptar Pedido', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          
          // Driver control deck for active selection
          if (activeRoutes.isNotEmpty && selectedOrder != null)
            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
                color: Colors.white,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('PEDIDO EN CURSO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
                      // Toggle Chat for driver
                      IconButton(
                        onPressed: () => setState(() => _showChat = true),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        icon: Badge(
                          label: Text(selectedOrder.chatLogs.where((l) => l['sender'] == 'client').length.toString()),
                          isLabelVisible: selectedOrder.chatLogs.where((l) => l['sender'] == 'client').isNotEmpty,
                          child: Icon(Icons.chat_bubble_outline, color: _getBrandColor(selectedOrder.brand), size: 20),
                        ),
                      )
                    ],
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: activeRoutes.any((o) => o.id == _selectedOrderId) ? _selectedOrderId : (activeRoutes.isNotEmpty ? activeRoutes.first.id : null),
                    decoration: const InputDecoration(
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    items: activeRoutes.map((o) {
                      return DropdownMenuItem(
                        value: o.id,
                        child: Text('${o.brand} (${o.client})', style: const TextStyle(fontSize: 12)),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setState(() {
                        _selectedOrderId = val;
                        _codeError = false;
                        _codeController.clear();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Ruta Restante', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          Text(
                            '${(2.4 * (1.0 - selectedOrder.progress / 100.0)).toStringAsFixed(1)} km',
                            style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Tiempo ETA', style: TextStyle(fontSize: 10, color: Colors.grey)),
                          Text(
                            '${selectedOrder.eta} min',
                            style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  
                  // Active state triggers
                  if (selectedOrder.status == 'accepted')
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => _startGPSRoute(selectedOrder!, firestoreService),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Iniciar Ruta GPS', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  if (selectedOrder.status == 'in_transit')
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () {
                          _routeTimers[selectedOrder!.id]?.cancel();
                          _routeTimers.remove(selectedOrder.id);
                          _routeSteps.remove(selectedOrder.id);
                          firestoreService.updateOrderStatus(selectedOrder.id, 'arrived');
                          firestoreService.updateOrderTracking(
                            selectedOrder.id,
                            currentX: _routes[selectedOrder.id]!.last['x']!,
                            currentY: _routes[selectedOrder.id]!.last['y']!,
                            progress: 100.0,
                            eta: 0,
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.amber[700],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Marcar como Llegado', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  if (selectedOrder.status == 'arrived')
                    Container(
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF3F4F6),
                        borderRadius: BorderRadius.circular(10.0),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('OTP DE VERIFICACIÓN (PIDE AL CLIENTE):', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: SizedBox(
                                  height: 38,
                                  child: TextField(
                                    controller: _codeController,
                                    textAlign: TextAlign.center,
                                    keyboardType: TextInputType.number,
                                    maxLength: 4,
                                    style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 4),
                                    decoration: const InputDecoration(
                                      counterText: '',
                                      contentPadding: EdgeInsets.zero,
                                      border: OutlineInputBorder(),
                                      fillColor: Colors.white,
                                      filled: true,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                height: 38,
                                child: FilledButton(
                                  onPressed: () {
                                    if (_codeController.text == selectedOrder!.passcode) {
                                      firestoreService.updateOrderStatus(selectedOrder.id, 'delivered');
                                      setState(() {
                                        _codeError = false;
                                        _codeController.clear();
                                        _selectedOrderId = null;
                                      });
                                    } else {
                                      setState(() {
                                        _codeError = true;
                                      });
                                    }
                                  },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF10B981),
                                    padding: const EdgeInsets.symmetric(horizontal: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  child: const Text('Validar', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                              )
                            ],
                          ),
                          if (_codeError)
                            const Padding(
                              padding: EdgeInsets.only(top: 6.0),
                              child: Text('❌ Código OTP incorrecto.', style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold)),
                            )
                        ],
                      ),
                    )
                ],
              ),
            )
        ],
      ),
    );
  }

  Widget _buildMapArea(List<Order> orders, Order? selectedOrder) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            painter: VectorMapPainter(
              activeOrder: selectedOrder,
              allOrders: orders,
            ),
          ),
        ),
        if (selectedOrder == null)
          const Center(
            child: Card(
              color: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Acepta un pedido disponible para ver la ruta optimizada',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 12),
                ),
              ),
            ),
          ),
        
        // Navigation Instructions HUD
        if (selectedOrder != null && selectedOrder.status == 'in_transit')
          Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 3)),
                ]
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.navigation, color: Color(0xFF10B981), size: 16),
                      SizedBox(width: 6),
                      Text('Gira a la derecha en 100 metros', style: TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text('Ruta de entrega hacia domicilio de ${selectedOrder.client}', style: const TextStyle(color: Colors.grey, fontSize: 10)),
                ],
              ),
            ),
          )
      ],
    );
  }
}
