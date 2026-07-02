import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:provider/provider.dart';
import 'firebase_options.dart';
import 'models/order.dart';
import 'models/app_user.dart';
import 'models/driver.dart';
import 'services/auth_service.dart';
import 'services/firestore_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services/notification_service.dart';
// ----------------------------------------------------------------------------
// CONFIGURACIÓN DE MAPBOX Y ENRUTAMIENTO REAL (OSRM)
// ----------------------------------------------------------------------------
String mapboxAccessToken = 'YOUR_MAPBOX_ACCESS_TOKEN';
String mapboxStyleId = 'streets-v12'; // e.g. streets-v12, satellite-streets-v12, dark-v11, light-v11

// Retorna la capa de mapas correspondiente (Mapbox si hay token, o OpenStreetMap de respaldo)
TileLayer buildMapTileLayer() {
  if (mapboxAccessToken.trim().isNotEmpty &&
      mapboxAccessToken != 'YOUR_MAPBOX_ACCESS_TOKEN' &&
      !mapboxAccessToken.startsWith('YOUR_')) {
    return TileLayer(
      urlTemplate: 'https://api.mapbox.com/styles/v1/mapbox/$mapboxStyleId/tiles/256/{z}/{x}/{y}@2x?access_token=$mapboxAccessToken',
      userAgentPackageName: 'com.example.cliente_celular',
    );
  } else {
    return TileLayer(
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.example.cliente_celular',
    );
  }
}

// Genera un recorrido en línea recta de respaldo si falla el API de OSRM
List<LatLng> getFallbackStraightRoute(LatLng start, LatLng end) {
  final List<LatLng> points = [];
  const int steps = 15;
  for (int i = 0; i <= steps; i++) {
    final double t = i / steps;
    points.add(LatLng(
      start.latitude + (end.latitude - start.latitude) * t,
      start.longitude + (end.longitude - start.longitude) * t,
    ));
  }
  return points;
}

// Consulta el API público gratuito de OSRM para obtener la ruta por calles en formato GeoJSON
Future<List<LatLng>> fetchOSRMRoute(LatLng start, LatLng end) async {
  try {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(
      'https://router.project-osrm.org/route/v1/driving/'
      '${start.longitude},${start.latitude};${end.longitude},${end.latitude}'
      '?overview=full&geometries=geojson'
    ));
    final response = await request.close();
    if (response.statusCode == 200) {
      final responseBody = await response.transform(utf8.decoder).join();
      final data = json.decode(responseBody);
      final routes = data['routes'] as List;
      if (routes.isNotEmpty) {
        final geometry = routes[0]['geometry'];
        final coordinates = geometry['coordinates'] as List;
        return coordinates.map<LatLng>((coord) {
          // GeoJSON es [longitud, latitud]
          return LatLng(coord[1] as double, coord[0] as double);
        }).toList();
      }
    }
  } catch (e) {
    debugPrint("Error fetching route from OSRM: $e");
  }
  return [];
}

// Diálogo interactivo para elegir el estilo visual del mapa
void showMapSettingsDialog(BuildContext context, VoidCallback onSaved) {
  String tempStyleId = mapboxStyleId;

  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: const [
                Icon(Icons.map_rounded, color: Color(0xFF10B981)),
                SizedBox(width: 8),
                Text(
                  'Estilo del Mapa',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selecciona el diseño visual para el mapa de seguimiento:',
                    style: TextStyle(fontSize: 12, color: Colors.black54, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: tempStyleId,
                    dropdownColor: Colors.white,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
                      ),
                    ),
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                    items: const [
                      DropdownMenuItem(value: 'streets-v12', child: Text('Calles Estándar')),
                      DropdownMenuItem(value: 'outdoors-v12', child: Text('Exteriores')),
                      DropdownMenuItem(value: 'light-v11', child: Text('Claro Premium')),
                      DropdownMenuItem(value: 'dark-v11', child: Text('Oscuro Premium')),
                      DropdownMenuItem(value: 'satellite-streets-v12', child: Text('Satélite Híbrido')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() {
                          tempStyleId = val;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar', style: TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
              ),
              FilledButton(
                onPressed: () {
                  mapboxStyleId = tempStyleId;
                  Navigator.pop(context);
                  onSaved();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                child: const Text('Aplicar', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ),
            ],
          );
        },
      );
    },
  );
}

// ----------------------------------------------------------------------------
// CONFIGURACIÓN DE AJUSTES GLOBALES (Tema y Notificaciones)
// ----------------------------------------------------------------------------
class AppSettings extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  bool _receiveNotifications = true;

  ThemeMode get themeMode => _themeMode;
  bool get receiveNotifications => _receiveNotifications;

  void toggleTheme(bool isDark) {
    _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  void setReceiveNotifications(bool value) {
    _receiveNotifications = value;
    notifyListeners();
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    
    // Inicializar el Servicio de Notificaciones Locales Reales
    final notificationService = NotificationService();
    await notificationService.init();
    await notificationService.requestPermissions();
  } catch (e) {
    debugPrint("Firebase connection failed: $e");
  }

  runApp(
    MultiProvider(
      providers: [
        Provider<FirestoreService>(create: (_) => FirestoreService()),
        Provider<AuthService>(create: (_) => AuthService()),
        ChangeNotifierProvider<AppSettings>(create: (_) => AppSettings()),
      ],
      child: const UnifiedDelivApp(),
    ),
  );
}

class UnifiedDelivApp extends StatelessWidget {
  const UnifiedDelivApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AppSettings>(
      builder: (context, settings, _) {
        return MaterialApp(
          title: 'DelivEcosys - App Unificada',
          debugShowCheckedModeBanner: false,
          themeMode: settings.themeMode,
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
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0F172A),
            fontFamily: 'Roboto',
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF3B82F6),
              brightness: Brightness.dark,
              background: const Color(0xFF0F172A),
            ),
            cardTheme: const CardThemeData(
              color: Color(0xFF1E293B),
              surfaceTintColor: Colors.transparent,
            ),
          ),
          home: const AuthWrapper(),
        );
      },
    );
  }
}

// ----------------------------------------------------------------------------
// Authentication Wrapper — escucha Firebase Auth y redirige por rol
// ----------------------------------------------------------------------------
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // Cargando estado de auth
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // No hay sesión activa → mostrar login
        if (!snapshot.hasData || snapshot.data == null) {
          return const LoginScreen();
        }

        // Hay sesión → cargar rol del usuario
        return FutureBuilder<AppUser?>(
          future: authService.getCurrentAppUser(),
          builder: (context, userSnap) {
            if (userSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            final appUser = userSnap.data;
            if (appUser == null) {
              return const LoginScreen();
            }

            if (appUser.isAdmin) {
              return AdminPanelScreen(appUser: appUser);
            } else if (appUser.isDriver) {
              return InAppNotificationOverlay(
                userEmail: appUser.email,
                userId: appUser.uid,
                userRole: 'driver',
                child: RiderDashboardScreen(
                  appUser: appUser,
                  onLogout: () => authService.signOut(),
                ),
              );
            } else {
              return InAppNotificationOverlay(
                userEmail: appUser.email,
                userId: appUser.uid,
                userRole: 'client',
                child: CustomerPhoneScreen(
                  appUser: appUser,
                  onLogout: () => authService.signOut(),
                ),
              );
            }
          },
        );
      },
    );
  }
}

// ----------------------------------------------------------------------------
// Login Screen — formulario único con redirección automática por rol
// ----------------------------------------------------------------------------
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isRegistering = false; // Alternar entre Login y Registro
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleAuthAction() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final name = _nameController.text.trim();

    if (email.isEmpty || password.isEmpty || (_isRegistering && name.isEmpty)) {
      setState(() => _errorMessage = 'Por favor completa todos los campos.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (_isRegistering) {
        await authService.registerWithEmail(name: name, email: email, password: password);
      } else {
        await authService.signIn(email, password);
      }
    } on FirebaseAuthException catch (e) {
      final authService = Provider.of<AuthService>(context, listen: false);
      setState(() => _errorMessage = authService.getErrorMessage(e));
    } catch (e) {
      setState(() => _errorMessage = 'Ocurrió un error. Intenta de nuevo.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = await authService.signInWithGoogle();
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    } on FirebaseAuthException catch (e) {
      final authService = Provider.of<AuthService>(context, listen: false);
      setState(() => _errorMessage = authService.getErrorMessage(e));
    } catch (e) {
      setState(() => _errorMessage = 'Error al iniciar sesión con Google.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleForgotPassword() async {
    final resetEmailController = TextEditingController(
      text: _emailController.text.trim(),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.lock_reset_rounded, color: Color(0xFF2563EB), size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Recuperar Contraseña',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ingresa tu correo electrónico y te enviaremos un enlace para restablecer tu contraseña.',
              style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: resetEmailController,
              keyboardType: TextInputType.emailAddress,
              style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14),
              decoration: InputDecoration(
                hintText: 'ejemplo@correo.com',
                hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                prefixIcon: const Icon(Icons.email_outlined, color: Color(0xFF94A3B8), size: 18),
                filled: true,
                fillColor: const Color(0xFFF1F5F9),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Enviar Enlace', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final email = resetEmailController.text.trim();
      if (email.isEmpty) {
        setState(() => _errorMessage = 'Ingresa un correo electrónico para recuperar tu contraseña.');
        return;
      }
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        await authService.sendPasswordResetEmail(email);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Se envió un enlace de recuperación a $email',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF10B981),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 5),
            ),
          );
          setState(() => _errorMessage = null);
        }
      } on FirebaseAuthException catch (e) {
        final authService = Provider.of<AuthService>(context, listen: false);
        setState(() => _errorMessage = authService.getErrorMessage(e));
      } catch (e) {
        setState(() => _errorMessage = 'No se pudo enviar el correo de recuperación.');
      }
    }
    resetEmailController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // Fondo blanco roto / gris muy claro
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28.0, vertical: 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo circular estilizado sin degradado, color plano
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB), // Azul corporativo plano
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withOpacity(0.2),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.local_shipping_rounded, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 20),
                const Text(
                  'DelivEcosys',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 28,
                    letterSpacing: 0.5,
                    color: Color(0xFF0F172A), // Letra oscura
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Sistema de Gestión de Entregas',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                ),
                const SizedBox(height: 32),

                // Card del formulario (Fondo blanco puro, borde gris sutil)
                Container(
                  constraints: const BoxConstraints(maxWidth: 400),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 24,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isRegistering ? 'Crear Cuenta' : 'Iniciar Sesión',
                        style: const TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isRegistering 
                            ? 'Regístrate para recibir tus paquetes' 
                            : 'Ingresa tus credenciales para continuar',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      ),
                      const SizedBox(height: 24),

                      // Campo Nombre (solo si nos registramos)
                      if (_isRegistering) ...[
                        _buildLabel('Tu Nombre Completo'),
                        const SizedBox(height: 6),
                        _buildTextField(
                          controller: _nameController,
                          hint: 'Juan Pérez',
                          icon: Icons.person_outline_rounded,
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Email
                      _buildLabel('Correo electrónico'),
                      const SizedBox(height: 6),
                      _buildTextField(
                        controller: _emailController,
                        hint: 'ejemplo@correo.com',
                        icon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 16),

                      // Password
                      _buildLabel('Contraseña'),
                      const SizedBox(height: 6),
                      _buildTextField(
                        controller: _passwordController,
                        hint: '••••••••',
                        icon: Icons.lock_outline_rounded,
                        obscure: _obscurePassword,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                            color: const Color(0xFF94A3B8),
                            size: 20,
                          ),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Enlace "¿Olvidaste tu contraseña?"
                      if (!_isRegistering)
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: _handleForgotPassword,
                            child: const Text(
                              '¿Olvidaste tu contraseña?',
                              style: TextStyle(
                                color: Color(0xFF2563EB),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 16),

                      // Error
                      if (_errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFCA5A5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(color: Color(0xFF991B1B), fontSize: 12),
                                ),
                              ),
                            ],
                          ),
                        ),

                      // Botón primario
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _handleAuthAction,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2563EB),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFF93C5FD),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _isRegistering ? 'Registrarse' : 'Ingresar',
                                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),

                      const SizedBox(height: 16),
                      Row(
                        children: const [
                          Expanded(child: Divider(color: Color(0xFFE2E8F0), thickness: 1)),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12.0),
                            child: Text(
                              'o',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                            ),
                          ),
                          Expanded(child: Divider(color: Color(0xFFE2E8F0), thickness: 1)),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Botón Google Sign-In
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _handleGoogleLogin,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF0F172A),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: Image.network(
                            'https://upload.wikimedia.org/wikipedia/commons/thumb/5/53/Google_%22G%22_Logo.svg/512px-Google_%22G%22_Logo.svg.png',
                            height: 18,
                            width: 18,
                            errorBuilder: (context, error, stackTrace) => const Icon(
                              Icons.g_mobiledata_rounded, 
                              color: Color(0xFF2563EB), 
                              size: 24,
                            ),
                          ),
                          label: const Text(
                            'Continuar con Google',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                // Botón alternador para registrarse / iniciar sesión
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isRegistering = !_isRegistering;
                      _errorMessage = null;
                    });
                  },
                  child: Text(
                    _isRegistering 
                        ? '¿Ya tienes cuenta? Inicia sesión' 
                        : '¿No tienes una cuenta? Regístrate aquí',
                    style: const TextStyle(
                      color: Color(0xFF2563EB), 
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF475569),
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Color(0xFF0F172A), fontSize: 14), // Letra oscura en el campo
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
        prefixIcon: Icon(icon, color: const Color(0xFF94A3B8), size: 18),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: const Color(0xFFF1F5F9), // Fondo del input gris claro
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Customer Phone Tracking Screen
// ----------------------------------------------------------------------------
class CustomerPhoneScreen extends StatefulWidget {
  final AppUser appUser;
  final VoidCallback onLogout;

  const CustomerPhoneScreen({
    super.key, 
    required this.appUser, 
    required this.onLogout
  });

  @override
  State<CustomerPhoneScreen> createState() => _CustomerPhoneScreenState();
}

class _CustomerPhoneScreenState extends State<CustomerPhoneScreen> {
  String? _selectedOrderId;
  bool _showChat = false;
  int _currentTab = 0; // 0 = Rastreo, 1 = Historial, 2 = Ajustes
  final Set<String> _ratedOrders = {}; // Órdenes calificadas en esta sesión
  final TextEditingController _chatController = TextEditingController();
  List<LatLng> _clientRoutePoints = [];
  String? _loadedRouteOrderId;
  String? _dismissedArrivedOrderId;
  final Map<String, String> _orderStatusCache = {};

  void _loadRouteForOrder(Order order) async {
    if (_loadedRouteOrderId == order.id && _clientRoutePoints.isNotEmpty) return;
    _loadedRouteOrderId = order.id;

    // Usamos la posición actual del repartidor guardada en Firestore como punto de inicio
    final start = LatLng(order.currentX, order.currentY);
    final end = LatLng(order.destLatitude, order.destLongitude);

    final points = await fetchOSRMRoute(start, end);
    if (points.isNotEmpty) {
      if (mounted) {
        setState(() {
          _clientRoutePoints = points;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _clientRoutePoints = getFallbackStraightRoute(start, end);
        });
      }
    }
  }

  void hideChat() {
    setState(() {
      _showChat = false;
    });
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _chatController.dispose();
    super.dispose();
  }

  Color _getBrandColor(String brand) {
    if (brand.contains('Amazon')) return const Color(0xFFFF9900);
    if (brand.contains('MercadoLibre')) return const Color(0xFF2563EB);
    if (brand.contains('DHL')) return const Color(0xFFCC0000);
    return Colors.blue;
  }

  // Diálogo interactivo premium de calificación del repartidor
  void _showRatingDialog(BuildContext context, Order order) {
    int rating = 5;
    final commentController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Column(
                children: [
                  const Icon(Icons.stars_rounded, color: Colors.amber, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    '¡Tu paquete ha llegado!',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Califica el servicio de ${order.driverName}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Estrellas interactivas
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final starValue = index + 1;
                      final isSelected = starValue <= rating;
                      return IconButton(
                        onPressed: () {
                          setDialogState(() {
                            rating = starValue;
                          });
                        },
                        icon: Icon(
                          isSelected ? Icons.star_rounded : Icons.star_border_rounded,
                          color: isSelected ? Colors.amber : Colors.grey.shade400,
                          size: 36,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: commentController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Escribe un comentario sobre la entrega (opcional)...',
                      hintStyle: const TextStyle(fontSize: 12, color: Colors.black38),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: const EdgeInsets.all(12),
                    ),
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ],
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: [
                FilledButton(
                  onPressed: () async {
                    // Guardar calificación en Firestore
                    await FirebaseFirestore.instance.collection('drivers').doc(order.driverId).collection('ratings').add({
                      'orderId': order.id,
                      'client': order.client,
                      'rating': rating,
                      'comment': commentController.text.trim(),
                      'timestamp': DateTime.now().millisecondsSinceEpoch,
                    });
                    
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('¡Muchas gracias por tu calificación!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  ),
                  child: const Text('Enviar Calificación', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Vista de historial de entregas pasadas
  Widget _buildHistoryView(List<Order> allOrders) {
    // Filtrar entregados de este cliente (que no estén archivados por el cliente)
    final historyOrders = allOrders.where((o) => o.status == 'delivered' && !o.clientArchived).toList();

    if (historyOrders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No tienes entregas pasadas registradas.',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black54),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: historyOrders.length,
      itemBuilder: (context, index) {
        final order = historyOrders[index];
        final brandColor = _getBrandColor(order.brand);

        return Card(
          color: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE5E7EB)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      order.brand,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: brandColor),
                    ),
                    const Card(
                      color: Color(0xFFD1FAE5),
                      elevation: 0,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        child: Text(
                          'ENTREGADO',
                          style: TextStyle(color: Color(0xFF065F46), fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  order.item,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                ),
                const SizedBox(height: 4),
                Text('Código de Orden: #${order.id.split('-').last.toUpperCase()}', style: const TextStyle(fontSize: 11, color: Colors.black45)),
                const Divider(height: 24, color: Color(0xFFF3F4F6)),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: brandColor.withOpacity(0.1),
                      child: Icon(Icons.person_rounded, size: 14, color: brandColor),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Entregado por:', style: TextStyle(fontSize: 9, color: Colors.black45)),
                          Text(
                            order.driverName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black87),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.archive_outlined, color: Colors.grey, size: 20),
                      tooltip: 'Archivar e ir a estado de no verlo más',
                      onPressed: () async {
                        final firestoreService = Provider.of<FirestoreService>(context, listen: false);
                        await firestoreService.archiveOrderForClient(order.id);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Pedido archivado e historial limpiado.'),
                              backgroundColor: Colors.blueGrey,
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _checkAndShowNotifications(List<Order> orders) {
    final settings = Provider.of<AppSettings>(context, listen: false);
    // Si el usuario desactivó las notificaciones en sus ajustes, no lanzamos nada
    if (!settings.receiveNotifications) return;

    for (final order in orders) {
      final previousStatus = _orderStatusCache[order.id];
      if (previousStatus != null && previousStatus != order.status) {
        // El estado cambió
        String title = '';
        String body = '';

        if (order.status == 'accepted') {
          title = '📦 ¡Paquete Asignado!';
          body = 'Tu pedido de ${order.brand} (${order.item}) ha sido asignado al repartidor ${order.driverName}.';
        } else if (order.status == 'in_transit') {
          title = '⚡ ¡Pedido en camino!';
          body = 'El repartidor va rumbo a tu dirección para entregarte: ${order.item}.';
        } else if (order.status == 'arrived') {
          title = '🔔 ¡El repartidor está afuera!';
          body = 'Tu paquete llegó. Entrégale este PIN para confirmar la entrega: ${order.passcode}';
        } else if (order.status == 'delivered') {
          title = '✓ ¡Paquete Entregado!';
          body = 'Se ha entregado con éxito tu producto: ${order.item}. ¡Gracias por usar DelivEcosys!';
        }

        if (title.isNotEmpty) {
          NotificationService().showNotification(
            id: order.id.hashCode,
            title: title,
            body: body,
          );
        }
      }
      // Actualizar la caché de estados
      _orderStatusCache[order.id] = order.status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);

    return Scaffold(
      body: SafeArea(
        child: StreamBuilder<List<Order>>(
          stream: firestoreService.getOrdersForClient(widget.appUser.uid),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final orders = snapshot.data ?? [];
            _checkAndShowNotifications(orders);

            // Si no hay órdenes y estamos en la pestaña 0 (Rastreo), mostrar estado vacío
            if (orders.isEmpty && _currentTab == 0) {
              return Column(
                children: [
                  _buildAppHeaderEmpty(),
                  Expanded(
                    child: _buildNoOrdersState(),
                  ),
                ],
              );
            }

            // Auto-seleccionar la primera orden si no hay selección
            if (orders.isNotEmpty && (_selectedOrderId == null || !orders.any((o) => o.id == _selectedOrderId))) {
              _selectedOrderId = orders.first.id;
            }

            final bool isLive = snapshot.hasData && orders.any((o) => o.id == _selectedOrderId);
            Order? activeOrder;
            if (orders.isNotEmpty && _selectedOrderId != null) {
              try {
                activeOrder = orders.firstWhere((o) => o.id == _selectedOrderId);
              } catch (_) {
                activeOrder = orders.first;
              }
            }

            // Monitorear e interceptar cuando el pedido cambie a entregado para detonar calificación
            if (activeOrder != null && activeOrder.status == 'delivered' && !_ratedOrders.contains(activeOrder.id)) {
              _ratedOrders.add(activeOrder.id);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _showRatingDialog(context, activeOrder!);
              });
            }

            if (activeOrder != null && activeOrder.status != 'pending') {
              _loadRouteForOrder(activeOrder);
            } else {
              _clientRoutePoints = [];
              _loadedRouteOrderId = null;
            }

            Widget currentView;
            switch (_currentTab) {
              case 1:
                currentView = _buildHistoryView(orders);
                break;
              case 2:
                currentView = _buildSettingsView();
                break;
              default:
                currentView = activeOrder == null
                    ? _buildNoOrdersState()
                    : (activeOrder.status == 'pending'
                        ? _buildEmptyState(activeOrder)
                        : _buildTrackingScreen(activeOrder, firestoreService));
            }

            return Stack(
              children: [
                Column(
                  children: [
                    // Header de la App
                    if (_currentTab == 0 && activeOrder != null)
                      _buildAppHeader(activeOrder, isLive: isLive, allOrders: orders)
                    else
                      _buildAppHeaderTitle(),

                    Expanded(
                      child: currentView,
                    ),
                  ],
                ),

                // Banner Superior Flotante Animado de Llegada
                if (activeOrder != null && activeOrder.status == 'arrived' && _dismissedArrivedOrderId != activeOrder.id)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Material(
                      elevation: 12,
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.transparent,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF2563EB).withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.2),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.flash_on_rounded, color: Colors.white, size: 20),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    '¡Tu Repartidor Llegó!',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Código de Entrega: ${activeOrder.passcode}',
                                    style: const TextStyle(fontSize: 11, color: Colors.white70, fontWeight: FontWeight.w500),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () {
                                setState(() {
                                  _dismissedArrivedOrderId = activeOrder!.id;
                                });
                              },
                              icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                // Chat Overlay panel
                if (_showChat && activeOrder != null)
                  _buildChatOverlay(activeOrder, firestoreService, 'client'),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentTab,
        onTap: (index) {
          setState(() {
            _currentTab = index;
            _showChat = false;
          });
        },
        selectedItemColor: const Color(0xFF2563EB),
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        elevation: 8,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.map_outlined),
            activeIcon: Icon(Icons.map),
            label: 'Rastreo',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history_rounded),
            label: 'Historial',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: 'Ajustes',
          ),
        ],
      ),
    );
  }

  Widget _buildAppHeader(Order order, {required bool isLive, required List<Order> allOrders}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo/Brand Avatar
          CircleAvatar(
            backgroundColor: _getBrandColor(order.brand).withOpacity(0.1),
            radius: 18,
            child: Icon(
              _getBrandIcon(order.brand),
              color: _getBrandColor(order.brand),
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          // Selector de pedido activo
          Expanded(
            child: Row(
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
                Flexible(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedOrderId,
                      dropdownColor: isDark ? const Color(0xFF1E293B) : Colors.white,
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.black54, size: 20),
                      style: TextStyle(
                        fontWeight: FontWeight.bold, 
                        color: isDark ? Colors.white : Colors.black87, 
                        fontSize: 13,
                        fontFamily: 'Roboto',
                      ),
                      isExpanded: true,
                      items: allOrders
                          .where((o) => o.status != 'delivered')
                          .map((o) => DropdownMenuItem(
                                value: o.id,
                                child: Text(
                                  '${o.brand}: ${o.item}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
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
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppHeaderEmpty() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CircleAvatar(
            backgroundColor: const Color(0xFFEEF2FF),
            radius: 18,
            child: Icon(Icons.local_shipping_rounded, color: const Color(0xFF2563EB), size: 18),
          ),
          Text(
            'DelivEcosys',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: isDark ? Colors.white : Colors.black87),
          ),
          const SizedBox(width: 36), // Espaciador visual
        ],
      ),
    );
  }

  // Estado vacío cuando el cliente no tiene paquetes asignados
  Widget _buildNoOrdersState() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 48.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2563EB).withOpacity(0.1),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF2563EB), size: 48),
          ),
          const SizedBox(height: 28),
          const Text(
            'Sin paquetes por el momento',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 20,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Cuando la paquetería registre un envío a tu nombre, aparecerá aquí automáticamente con seguimiento en tiempo real.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF64748B),
              fontSize: 13,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline_rounded, color: Color(0xFF16A34A), size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Tu correo electrónico está vinculado a esta cuenta. El administrador usará tu correo para asignarte paquetes.',
                    style: TextStyle(color: Color(0xFF166534), fontSize: 11, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
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
      padding: const EdgeInsets.all(20),
      children: [
        // Map Container con diseño tipo Glassmorphism
        Container(
          height: 280,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFECEFF1), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Stack(
              children: [
                Positioned.fill(
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: LatLng(order.currentX, order.currentY),
                      initialZoom: 15.0,
                      minZoom: 10,
                      maxZoom: 18,
                    ),
                    children: [
                      buildMapTileLayer(),
                      if (_clientRoutePoints.isNotEmpty)
                        PolylineLayer(
                          polylines: [
                            Polyline(
                              points: _clientRoutePoints,
                              color: brandColor,
                              strokeWidth: 4.5,
                              borderColor: Colors.white,
                              borderStrokeWidth: 1.5,
                            ),
                          ],
                        ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(order.currentX, order.currentY),
                            width: 44,
                            height: 44,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(color: brandColor, width: 3),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black26, 
                                    blurRadius: 6,
                                    offset: Offset(0, 3)
                                  )
                                ],
                              ),
                              child: Icon(Icons.motorcycle_rounded, color: brandColor, size: 22),
                            ),
                          ),
                          Marker(
                            point: LatLng(order.destLatitude, order.destLongitude),
                            width: 44,
                            height: 44,
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 6,
                                    offset: Offset(0, 3)
                                  )
                                ],
                              ),
                              child: const Icon(
                                Icons.location_on_rounded,
                                color: Colors.redAccent,
                                size: 28,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Positioned(
                  top: 12,
                  right: 12,
                  child: Material(
                    type: MaterialType.transparency,
                    child: Tooltip(
                      message: 'Configurar Mapa',
                      child: FloatingActionButton.small(
                        heroTag: 'map_settings_client_${order.id}',
                        onPressed: () {
                          showMapSettingsDialog(context, () {
                            setState(() {});
                          });
                        },
                        backgroundColor: Colors.white,
                        elevation: 3,
                        child: const Icon(Icons.layers_rounded, color: Colors.black87, size: 20),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFECEFF1)),
                      boxShadow: const [
                        BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                      ]
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: brandColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          order.status == 'accepted'
                              ? 'Conductor asignado'
                              : (order.status == 'in_transit' 
                                  ? 'Repartidor en ruta' 
                                  : (order.status == 'arrived' ? '¡Llegó a tu destino!' : 'Paquete entregado')),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.black87),
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

        // Alerta Destacada cuando el repartidor ha llegado
        if (order.status == 'arrived') ...[
          Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF10B981), Color(0xFF059669)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withOpacity(0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                )
              ],
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_active_rounded, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Text(
                        '¡EL REPARTIDOR HA LLEGADO!',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text(
                  'Muestra este código de seguridad para recibir y confirmar tu paquete:',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                    ],
                  ),
                  child: Text(
                    order.passcode,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF059669),
                      letterSpacing: 4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Información de entrega y Código de Seguridad (Passcode)
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Paquete', style: TextStyle(fontSize: 10, color: Colors.black45, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      order.item,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: brandColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: brandColor.withOpacity(0.15)),
                ),
                child: Column(
                  children: [
                    Text(
                      'CÓDIGO',
                      style: TextStyle(fontSize: 8, color: brandColor, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      order.passcode,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: brandColor, letterSpacing: 0.5),
                    )
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Tarjeta Premium de Repartidor
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
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
              FutureBuilder<DocumentSnapshot>(
                future: FirebaseFirestore.instance.collection('drivers').doc(order.driverId).get(),
                builder: (context, snapshot) {
                  String avatarUrl = '';
                  if (snapshot.hasData && snapshot.data!.exists) {
                    final data = snapshot.data!.data() as Map<String, dynamic>?;
                    if (data != null) {
                      avatarUrl = data['photoUrl'] ?? '';
                    }
                  }
                  return CircleAvatar(
                    radius: 24,
                    backgroundColor: brandColor.withOpacity(0.1),
                    backgroundImage: avatarUrl.isNotEmpty ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl.isEmpty ? Icon(Icons.person_rounded, color: brandColor, size: 24) : null,
                  );
                },
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.driverName, 
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.electric_moped, size: 12, color: brandColor),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            order.driverVehicle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {},
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF9FAFB),
                  padding: const EdgeInsets.all(10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                ),
                icon: Icon(Icons.phone, color: brandColor, size: 18),
              ),
              const SizedBox(width: 6),
              IconButton(
                onPressed: () => setState(() => _showChat = true),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFF9FAFB),
                  padding: const EdgeInsets.all(10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                  ),
                ),
                icon: Icon(Icons.chat_bubble_outline, color: brandColor, size: 18),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Progreso de envío
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ],
          ),
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ORDEN: #${order.id.split('-').last.toUpperCase()}', style: const TextStyle(fontSize: 9, color: Colors.black45, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        _getProgressTitle(order.status), 
                        style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Llegada estimada', style: TextStyle(fontSize: 9, color: Colors.black45, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(
                        '${order.eta} min', 
                        style: TextStyle(color: brandColor, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ],
                  )
                ],
              ),
              const SizedBox(height: 24),
              
              // Stepper Lineal Premium
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

    Widget stepNode(int stepIndex, String title, IconData icon) {
      bool isDone = stepIndex <= activeStep;
      bool isCurrent = stepIndex == activeStep;
      return Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDone ? brandColor : const Color(0xFFF3F4F6),
              border: Border.all(
                color: isDone ? Colors.white : const Color(0xFFE5E7EB),
                width: 2.0,
              ),
              boxShadow: isDone 
                  ? [BoxShadow(color: brandColor.withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 3))]
                  : [],
            ),
            child: Icon(
              icon,
              size: 14,
              color: isDone ? Colors.white : Colors.black38,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            title, 
            style: TextStyle(
              fontSize: 9.5, 
              color: isCurrent ? brandColor : (isDone ? Colors.black87 : Colors.black38), 
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
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6), 
                borderRadius: BorderRadius.circular(4)
              ),
            ),
            Positioned(
              left: 20,
              right: 20,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: progressWidth,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: brandColor, 
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            stepNode(0, 'Aceptado', Icons.receipt_long_rounded),
            stepNode(1, 'En Camino', Icons.motorcycle_rounded),
            stepNode(2, 'Llegó', Icons.pin_drop_rounded),
            stepNode(3, 'Entregado', Icons.done_all_rounded),
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

  IconData _getBrandIcon(String brand) {
    if (brand.contains('Amazon')) return Icons.shopping_bag_rounded;
    if (brand.contains('MercadoLibre')) return Icons.shopping_cart_rounded;
    return Icons.local_shipping_rounded;
  }

  String _getProgressTitle(String status) {
    if (status == 'accepted') return 'Conductor asignado';
    if (status == 'in_transit') return 'Repartidor en camino';
    if (status == 'arrived') return '¡Repartidor afuera!';
    if (status == 'delivered') return '✓ Entregado con éxito';
    return 'Procesando';
  }

  // Header de la app estático para pantallas secundarias
  Widget _buildAppHeaderTitle() {
    String title = '';
    IconData icon = Icons.info_outline;
    if (_currentTab == 1) {
      title = 'Historial de Entregas';
      icon = Icons.history_rounded;
    } else if (_currentTab == 2) {
      title = 'Ajustes del Sistema';
      icon = Icons.settings_rounded;
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        border: Border(bottom: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE5E7EB))),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2563EB), size: 20),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  // Vista de Ajustes Premium y Configuración
  Widget _buildSettingsView() {
    final settings = Provider.of<AppSettings>(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Tarjeta de perfil
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: const Color(0xFF2563EB).withOpacity(0.1),
                  child: const Icon(Icons.person_rounded, size: 28, color: Color(0xFF2563EB)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.appUser.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.appUser.email,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'CLIENTE',
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFF2563EB)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        
        const SizedBox(height: 24),
        const Text(
          'PREFERENCIAS DE LA APLICACIÓN',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
        ),
        const SizedBox(height: 10),

        // Ajustes de la App
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              // Interruptor de Modo Oscuro
              SwitchListTile(
                title: const Text('Modo Noche', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('Cambiar la aplicación a colores oscuros', style: TextStyle(fontSize: 11, color: Colors.grey)),
                value: settings.themeMode == ThemeMode.dark,
                activeColor: const Color(0xFF2563EB),
                secondary: const Icon(Icons.dark_mode_outlined),
                onChanged: (val) {
                  settings.toggleTheme(val);
                },
              ),
              const Divider(height: 1),
              // Recibir Notificaciones
              SwitchListTile(
                title: const Text('Notificaciones en Tiempo Real', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('Recibir avisos emergentes sobre tus entregas', style: TextStyle(fontSize: 11, color: Colors.grey)),
                value: settings.receiveNotifications,
                activeColor: const Color(0xFF2563EB),
                secondary: const Icon(Icons.notifications_active_outlined),
                onChanged: (val) {
                  settings.setReceiveNotifications(val);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text(
          'INFORMACIÓN Y SOPORTE',
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
        ),
        const SizedBox(height: 10),

        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0)),
          ),
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.help_outline_rounded),
                title: const Text('Centro de Soporte', style: TextStyle(fontSize: 13)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Soporte simulado - Contacta al Administrador.')),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Acerca de DelivEcosys', style: TextStyle(fontSize: 13)),
                subtitle: const Text('Versión 1.0.0 (Xiaomi X7 Premium Edition)', style: TextStyle(fontSize: 10)),
                trailing: const Icon(Icons.chevron_right, size: 18),
                onTap: () {},
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),
        ElevatedButton.icon(
          onPressed: widget.onLogout,
          icon: const Icon(Icons.logout),
          label: const Text('Cerrar Sesión'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red.shade50,
            foregroundColor: Colors.red,
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
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
                          pState?.hideChat();
                        } else {
                          final pState = context.findAncestorStateOfType<_RiderDashboardScreenState>();
                          pState?.hideChat();
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
  final AppUser appUser;
  final VoidCallback onLogout;

  const RiderDashboardScreen({
    super.key,
    required this.appUser,
    required this.onLogout,
  });

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
  StreamSubscription<Position>? _positionStreamSubscription;
  List<LatLng> _riderRoutePoints = [];
  String? _riderLoadedRouteOrderId;

  void _loadRouteForRider(Order order) async {
    if (_riderLoadedRouteOrderId == order.id && _riderRoutePoints.isNotEmpty) return;
    _riderLoadedRouteOrderId = order.id;

    // Intentar obtener posición GPS real; si falla, usar la posición guardada del pedido
    LatLng start;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 4),
      );
      start = LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      start = LatLng(order.currentX, order.currentY);
    }
    final end = LatLng(order.destLatitude, order.destLongitude);

    final points = await fetchOSRMRoute(start, end);
    if (points.isNotEmpty) {
      if (mounted) {
        setState(() {
          _riderRoutePoints = points;
        });
      }
    } else {
      if (mounted) {
        setState(() {
          _riderRoutePoints = getFallbackStraightRoute(start, end);
        });
      }
    }
  }

  void hideChat() {
    setState(() {
      _showChat = false;
    });
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Servicio de ubicación desactivado. Usando simulación de respaldo.')),
        );
      }
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permisos de ubicación denegados. Usando simulación.')),
          );
        }
        return false;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permisos denegados permanentemente. Usando simulación.')),
        );
      }
      return false;
    }
    return true;
  }

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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handleLocationPermission();
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    for (var timer in _routeTimers.values) {
      timer.cancel();
    }
    _routeTimers.clear();
    _codeController.dispose();
    super.dispose();
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295; // pi / 180
    final double a = 0.5 - math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) * math.cos(lat2 * p) *
            (1 - math.cos((lon2 - lon1) * p)) / 2;
    return 12742 * math.asin(math.sqrt(a)) * 1000; // 2 * R * asin(sqrt(a)) in meters
  }

  void _startGPSRoute(Order order, FirestoreService service) async {
    // Si ya hay una ruta activa (sea de GPS real o simulación), no hacer nada
    if (_positionStreamSubscription != null || _routeTimers[order.id]?.isActive == true) return;

    // Actualizar estado del pedido a en tránsito
    service.updateOrderStatus(order.id, 'in_transit');

    // Intentar obtener permisos de ubicación
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) {
      // Usar simulación de respaldo si no hay permisos
      _startSimulatedRouteFallback(order, service);
      return;
    }

    Position? startPosition;
    try {
      startPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
    } catch (e) {
      debugPrint("Error getting current position: $e. Using fallback simulation.");
      _startSimulatedRouteFallback(order, service);
      return;
    }

    final double startLat = startPosition.latitude;
    final double startLon = startPosition.longitude;

    // Escribir posición real del repartidor en Firestore INMEDIATAMENTE
    // para que el cliente vea el punto de inicio correcto en su mapa
    service.updateOrderTracking(
      order.id,
      currentX: startLat,
      currentY: startLon,
      progress: order.progress,
      eta: order.eta,
    );

    // Destino real de la entrega en Firestore (se obtiene del documento del pedido)
    final double destLat = order.destLatitude;
    final double destLon = order.destLongitude;

    // Distancia total real en metros
    final double totalDistance = _calculateDistance(startLat, startLon, destLat, destLon);

    // Configurar el stream del GPS real
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 2, // Actualiza cada 2 metros de movimiento
    );

    _positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen((Position position) {
      final double currentLat = position.latitude;
      final double currentLon = position.longitude;

      // Calcular distancia restante al destino
      final double distToDest = _calculateDistance(currentLat, currentLon, destLat, destLon);

      // Calcular distancia y progreso real (0.0 a 100.0)
      final double distFromStart = _calculateDistance(startLat, startLon, currentLat, currentLon);
      double progressPercent = totalDistance > 0 ? (distFromStart / totalDistance) * 100.0 : 0.0;
      progressPercent = progressPercent.clamp(0.0, 100.0);

      // Calcular ETA dinámico
      double speed = position.speed;
      if (speed < 0.5) speed = 1.4; // 1.4 m/s caminando por defecto
      
      final int remainingMinutes = (distToDest / speed / 60.0).round();

      // Guardamos la latitud actual en currentX y la longitud en currentY en Firestore
      service.updateOrderTracking(
        order.id,
        currentX: currentLat,
        currentY: currentLon,
        progress: progressPercent,
        eta: remainingMinutes,
      );

      // Si el repartidor está a menos de 10 metros del destino real
      if (distToDest < 10.0 || progressPercent >= 98.0) {
        _positionStreamSubscription?.cancel();
        _positionStreamSubscription = null;
        service.updateOrderStatus(order.id, 'arrived');
        service.updateOrderTracking(
          order.id,
          currentX: destLat,
          currentY: destLon,
          progress: 100.0,
          eta: 0,
        );
      }
    }, onError: (err) {
      debugPrint("Error in location stream: $err. Switching to fallback.");
      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = null;
      _startSimulatedRouteFallback(order, service);
    });
  }

  void _startSimulatedRouteFallback(Order order, FirestoreService service) async {
    if (_routeTimers[order.id]?.isActive == true) return;
    
    _routeSteps[order.id] = 0;
    
    service.updateOrderStatus(order.id, 'in_transit');

    // Punto de inicio: intentar GPS real; si falla, usar posición actual guardada en el pedido
    LatLng start;
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 4),
      );
      start = LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      // Usar última posición conocida del repartidor almacenada en Firestore
      start = LatLng(order.currentX, order.currentY);
    }
    final end = LatLng(order.destLatitude, order.destLongitude);

    // Obtener ruta real de OSRM o recurrir al respaldo en línea recta
    List<LatLng> routePoints = await fetchOSRMRoute(start, end);
    if (routePoints.isEmpty) {
      routePoints = getFallbackStraightRoute(start, end);
    }

    final int totalSteps = routePoints.length;
    // Ajustar duración por paso para que dure ~20 segundos en total (mínimo 150ms, máximo 1000ms por paso)
    final int stepDurationMs = (20000 / totalSteps).round().clamp(150, 1000);

    _routeTimers[order.id] = Timer.periodic(Duration(milliseconds: stepDurationMs), (timer) async {
      int currentStep = _routeSteps[order.id] ?? 0;
      if (currentStep >= totalSteps - 1) {
        timer.cancel();
        _routeTimers.remove(order.id);
        _routeSteps.remove(order.id);
        service.updateOrderStatus(order.id, 'arrived');
        service.updateOrderTracking(
          order.id,
          currentX: end.latitude,
          currentY: end.longitude,
          progress: 100.0,
          eta: 0,
        );
        return;
      }

      currentStep++;
      _routeSteps[order.id] = currentStep;
      
      final LatLng currentPos = routePoints[currentStep];
      final double progressPercent = (currentStep / (totalSteps - 1)) * 100.0;
      
      // Calcular ETA dinámico basado en distancia restante
      final double remainingDistance = _calculateDistance(
        currentPos.latitude,
        currentPos.longitude,
        end.latitude,
        end.longitude,
      );
      // Asumimos velocidad promedio de 30 km/h (8.3 m/s) para el repartidor
      final int remainingMinutes = (remainingDistance / 8.3 / 60.0).round().clamp(1, 15);

      service.updateOrderTracking(
        order.id,
        currentX: currentPos.latitude,
        currentY: currentPos.longitude,
        progress: progressPercent,
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
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.navigation_outlined, color: Color(0xFF10B981), size: 20),
              SizedBox(width: 6),
              Text(
                'DelivEcosys',
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
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('drivers').doc(widget.appUser.uid).snapshots(),
        builder: (context, driverSnap) {
          if (driverSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!driverSnap.hasData || !driverSnap.data!.exists) {
            return const Center(
              child: Text(
                'No se encontró información de tu repartidor.\nContacta al Administrador.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            );
          }
          final driverData = driverSnap.data!.data() as Map<String, dynamic>;
          final driver = Driver.fromMap(widget.appUser.uid, driverData);

          return StreamBuilder<List<Order>>(
            stream: firestoreService.getOrdersStream(),
            builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

              final allOrders = snapshot.data ?? [];
              
              // Filtrar pedidos para mostrar:
              // 1. Pedidos sin asignar ('pending')
              // 2. Pedidos asignados a este repartidor y no archivados
              final orders = allOrders.where((o) {
                return (o.status == 'pending' || o.driverId == widget.appUser.uid) && !o.driverArchived;
              }).toList();

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

              if (selectedOrder != null) {
                _loadRouteForRider(selectedOrder);
              } else {
                _riderRoutePoints = [];
                _riderLoadedRouteOrderId = null;
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
                              child: _buildSidebar(orders, activeRoutes, selectedOrder, firestoreService, driver),
                            ),
                            // Right map view
                            Expanded(
                              child: _buildMapArea(allOrders, selectedOrder),
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
                                    _buildSidebar(orders, activeRoutes, selectedOrder, firestoreService, driver, fullWidth: true),
                                    _buildMapArea(allOrders, selectedOrder),
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
    Driver driver,
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
                        Row(
                          children: [
                            const Icon(Icons.shopping_bag_outlined, size: 14, color: Colors.black54),
                            const SizedBox(width: 6),
                            Text('Producto: ${order.item}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.person_outline, size: 14, color: Colors.black54),
                            const SizedBox(width: 6),
                            Text('Cliente: ${order.client}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (order.status == 'pending')
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton(
                              onPressed: () {
                                firestoreService.assignDriverToOrder(
                                  order.id,
                                  driverId: driver.uid,
                                  driverName: driver.name,
                                  driverVehicle: '${driver.vehicle} (${driver.plate})',
                                );
                                Provider.of<AuthService>(context, listen: false)
                                    .updateDriverStatus(driver.uid, 'busy');
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Aceptar Pedido', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ),
                          ),
                        if (order.status == 'delivered' && order.driverId == widget.appUser.uid)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await firestoreService.archiveOrderForDriver(order.id);
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Entrega archivada correctamente.'),
                                      backgroundColor: Colors.blueGrey,
                                    ),
                                  );
                                }
                              },
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.blueGrey,
                                side: const BorderSide(color: Colors.blueGrey),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              icon: const Icon(Icons.archive_outlined, size: 16),
                              label: const Text('Archivar Entrega', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: () async {
                              final url = 'https://www.google.com/maps/search/?api=1&query=${selectedOrder.destLatitude},${selectedOrder.destLongitude}';
                              if (await canLaunchUrl(Uri.parse(url))) {
                                await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('No se pudo abrir el mapa de navegación externa')),
                                  );
                                }
                              }
                            },
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.only(right: 12),
                            icon: Icon(Icons.near_me_rounded, color: _getBrandColor(selectedOrder.brand), size: 20),
                            tooltip: 'Navegar en Google Maps',
                          ),
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
                          ),
                        ],
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
                      return DropdownMenuItem<String>(
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
                        onPressed: () => _startGPSRoute(selectedOrder, firestoreService),
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
                          _routeTimers[selectedOrder.id]?.cancel();
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
                                    if (_codeController.text == selectedOrder.passcode) {
                                      firestoreService.updateOrderStatus(selectedOrder.id, 'delivered');
                                      Provider.of<AuthService>(context, listen: false)
                                          .updateDriverStatus(driver.uid, 'available');
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
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.error_outline, color: Colors.red, size: 14),
                                  SizedBox(width: 4),
                                  Text(
                                    'Código OTP incorrecto.',
                                    style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
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
    // Si hay un pedido seleccionado, centrar en la ubicación del repartidor. Si no, en la bodega.
    final LatLng initialCenter = selectedOrder != null
        ? LatLng(selectedOrder.currentX, selectedOrder.currentY)
        : const LatLng(20.3720, -100.0190);

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: selectedOrder != null ? 15.0 : 13.5,
              minZoom: 10,
              maxZoom: 18,
            ),
            children: [
              buildMapTileLayer(),
              if (selectedOrder != null && _riderRoutePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _riderRoutePoints,
                      color: _getBrandColor(selectedOrder.brand),
                      strokeWidth: 4.0,
                      borderColor: Colors.white,
                      borderStrokeWidth: 1.0,
                    ),
                  ],
                ),
              MarkerLayer(
                markers: [
                  // Si no hay pedido seleccionado, mostrar TODOS los destinos de pedidos disponibles
                  if (selectedOrder == null)
                    ...orders.map((o) {
                      final isPending = o.status == 'pending';
                      final color = _getBrandColor(o.brand);
                      return Marker(
                        point: LatLng(o.destLatitude, o.destLongitude),
                        width: 30,
                        height: 30,
                        child: Icon(
                          Icons.location_on_rounded,
                          color: isPending ? color : Colors.grey,
                          size: 24,
                        ),
                      );
                    })
                  else ...[
                    // Conductor/Repartidor
                    Marker(
                      point: LatLng(selectedOrder.currentX, selectedOrder.currentY),
                      width: 36,
                      height: 36,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
                        ),
                        child: Icon(
                          Icons.motorcycle_rounded,
                          color: _getBrandColor(selectedOrder.brand),
                          size: 20,
                        ),
                      ),
                    ),
                    // Destino (Casa Cliente)
                    Marker(
                      point: LatLng(selectedOrder.destLatitude, selectedOrder.destLongitude),
                      width: 36,
                      height: 36,
                      child: Icon(
                        Icons.location_on_rounded,
                        color: _getBrandColor(selectedOrder.brand),
                        size: 28,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        Positioned(
          top: 12,
          right: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Material(
                type: MaterialType.transparency,
                child: Tooltip(
                  message: 'Configurar Mapa',
                  child: FloatingActionButton.small(
                    heroTag: selectedOrder != null
                        ? 'map_settings_rider_${selectedOrder.id}'
                        : 'map_settings_rider_none',
                    onPressed: () {
                      showMapSettingsDialog(context, () {
                        setState(() {});
                      });
                    },
                    backgroundColor: Colors.white.withOpacity(0.9),
                    elevation: 2,
                    child: const Icon(Icons.layers_rounded, color: Colors.black87, size: 20),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (selectedOrder == null)
          const Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: Card(
              color: Colors.white,
              surfaceTintColor: Colors.white,
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF10B981), size: 18),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Acepta un pedido disponible para iniciar el rastreo GPS en tiempo real.',
                        style: TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
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
                  Row(
                    children: [
                      const Icon(Icons.navigation, color: Color(0xFF10B981), size: 16),
                      const SizedBox(width: 6),
                      Text('Ruta activa hacia cliente: ${selectedOrder.client}', style: const TextStyle(color: Color(0xFF047857), fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  const Text('Sigue la ruta en el mapa real usando tu ubicación GPS.', style: TextStyle(color: Colors.grey, fontSize: 10)),
                ],
              ),
            ),
          )
      ],
    );
  }
}

// ----------------------------------------------------------------------------
// Admin Panel Screen — Gestiona repartidores y asignación de pedidos (Colores claros y sin emojis)
// ----------------------------------------------------------------------------
class AdminPanelScreen extends StatefulWidget {
  final AppUser appUser;
  const AdminPanelScreen({super.key, required this.appUser});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _formKey = GlobalKey<FormState>();
  
  // Controladores de formulario
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  final _vehicleController = TextEditingController();
  final _plateController = TextEditingController();
  
  bool _isCreatingDriver = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    _vehicleController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  void _showAddDriverDialog() {
    _nameController.clear();
    _emailController.clear();
    _passwordController.clear();
    _phoneController.clear();
    _vehicleController.clear();
    _plateController.clear();
    setState(() => _errorMessage = null);

    String selectedVehicleType = 'Motocicleta';
    String selectedPhotoUrl = '';

    // Lista de avatares predeterminados súper profesionales de ejemplo
    final listAvatars = [
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&q=80&w=150',
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&q=80&w=150',
      'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&q=80&w=150',
      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&q=80&w=150',
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                'Registrar Nuevo Repartidor',
                style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                          ),
                        ),
                      
                      // Selector de foto de perfil
                      const Text(
                        'Foto de Perfil (Opcional)',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: Colors.grey.shade100,
                            backgroundImage: selectedPhotoUrl.isNotEmpty ? NetworkImage(selectedPhotoUrl) : null,
                            child: selectedPhotoUrl.isEmpty ? const Icon(Icons.person, color: Colors.grey, size: 28) : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Elige una imagen ilustrativa:',
                                  style: TextStyle(fontSize: 10, color: Colors.black45),
                                ),
                                const SizedBox(height: 4),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: listAvatars.map((url) {
                                      final isSelected = selectedPhotoUrl == url;
                                      return GestureDetector(
                                        onTap: () {
                                          setDialogState(() {
                                            selectedPhotoUrl = url;
                                          });
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.only(right: 6),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isSelected ? const Color(0xFF3B82F6) : Colors.transparent,
                                              width: 2,
                                            ),
                                          ),
                                          child: CircleAvatar(
                                            radius: 16,
                                            backgroundImage: NetworkImage(url),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      _buildDialogField(_nameController, 'Nombre Completo', Icons.person),
                      const SizedBox(height: 12),
                      _buildDialogField(_emailController, 'Correo Electrónico', Icons.email, keyboardType: TextInputType.emailAddress),
                      const SizedBox(height: 12),
                      _buildDialogField(_passwordController, 'Contraseña', Icons.lock, obscure: true),
                      const SizedBox(height: 12),
                      _buildDialogField(_phoneController, 'Teléfono', Icons.phone, keyboardType: TextInputType.phone),
                      const SizedBox(height: 16),

                      // Selección de Vehículo (Lista desplegable/Dropdown)
                      const Text(
                        'Tipo de Vehículo',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: selectedVehicleType,
                        dropdownColor: Colors.white,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          prefixIcon: const Icon(Icons.commute, size: 18),
                        ),
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                        items: const [
                          DropdownMenuItem(value: 'Motocicleta', child: Text('Motocicleta')),
                          DropdownMenuItem(value: 'Automóvil', child: Text('Automóvil')),
                          DropdownMenuItem(value: 'Bicicleta', child: Text('Bicicleta')),
                          DropdownMenuItem(value: 'Camioneta', child: Text('Camioneta')),
                          DropdownMenuItem(value: 'A pie', child: Text('A pie')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedVehicleType = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildDialogField(_vehicleController, 'Modelo del Vehículo (ej. Cargo 150)', Icons.motorcycle),
                      const SizedBox(height: 12),
                      _buildDialogField(_plateController, 'Placa (ej. FHJ-429)', Icons.credit_card),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: _isCreatingDriver ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.black54)),
                ),
                ElevatedButton(
                  onPressed: _isCreatingDriver
                      ? null
                      : () async {
                          if (_formKey.currentState!.validate()) {
                            setDialogState(() => _isCreatingDriver = true);
                            try {
                              final authService = Provider.of<AuthService>(context, listen: false);
                              // Guardamos el tipo de vehículo junto con la descripción
                              final fullVehicleDescription = '$selectedVehicleType - ${_vehicleController.text.trim()}';
                              
                              await authService.createDriver(
                                name: _nameController.text.trim(),
                                email: _emailController.text.trim(),
                                password: _passwordController.text,
                                phone: _phoneController.text.trim(),
                                vehicle: fullVehicleDescription,
                                plate: _plateController.text.trim(),
                                photoUrl: selectedPhotoUrl,
                              );

                              if (mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Repartidor registrado con éxito'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } on FirebaseAuthException catch (e) {
                              final authService = Provider.of<AuthService>(context, listen: false);
                              setDialogState(() {
                                _errorMessage = authService.getErrorMessage(e);
                              });
                            } catch (e) {
                              setDialogState(() {
                                _errorMessage = 'Error: $e';
                              });
                            } finally {
                              setDialogState(() => _isCreatingDriver = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: _isCreatingDriver
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Registrar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Diálogo para Editar un Repartidor Creado
  void _showEditDriverDialog(Driver driver) {
    _nameController.text = driver.name;
    _phoneController.text = driver.phone;
    _plateController.text = driver.plate;
    
    // Extraer tipo de vehículo y descripción
    String selectedVehicleType = 'Motocicleta';
    String vehicleDetail = driver.vehicle;
    if (driver.vehicle.contains(' - ')) {
      final parts = driver.vehicle.split(' - ');
      selectedVehicleType = parts[0];
      vehicleDetail = parts.sublist(1).join(' - ');
    }
    _vehicleController.text = vehicleDetail;
    
    String selectedPhotoUrl = driver.photoUrl;
    bool isSaving = false;
    setState(() => _errorMessage = null);

    final listAvatars = [
      'https://images.unsplash.com/photo-1534528741775-53994a69daeb?auto=format&fit=crop&q=80&w=150',
      'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?auto=format&fit=crop&q=80&w=150',
      'https://images.unsplash.com/photo-1506794778202-cad84cf45f1d?auto=format&fit=crop&q=80&w=150',
      'https://images.unsplash.com/photo-1494790108377-be9c29b29330?auto=format&fit=crop&q=80&w=150',
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                'Editar Datos de Repartidor',
                style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_errorMessage != null)
                        Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.red.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                          ),
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                          ),
                        ),
                      
                      // Foto de Perfil
                      const Text(
                        'Foto de Perfil',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 28,
                            backgroundColor: Colors.grey.shade100,
                            backgroundImage: selectedPhotoUrl.isNotEmpty ? NetworkImage(selectedPhotoUrl) : null,
                            child: selectedPhotoUrl.isEmpty ? const Icon(Icons.person, color: Colors.grey, size: 28) : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Cambiar imagen:',
                                  style: TextStyle(fontSize: 10, color: Colors.black45),
                                ),
                                const SizedBox(height: 4),
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: Row(
                                    children: listAvatars.map((url) {
                                      final isSelected = selectedPhotoUrl == url;
                                      return GestureDetector(
                                        onTap: () {
                                          setDialogState(() {
                                            selectedPhotoUrl = url;
                                          });
                                        },
                                        child: Container(
                                          margin: const EdgeInsets.only(right: 6),
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: isSelected ? const Color(0xFF3B82F6) : Colors.transparent,
                                              width: 2,
                                            ),
                                          ),
                                          child: CircleAvatar(
                                            radius: 16,
                                            backgroundImage: NetworkImage(url),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      _buildDialogField(_nameController, 'Nombre Completo', Icons.person),
                      const SizedBox(height: 12),
                      _buildDialogField(_phoneController, 'Teléfono', Icons.phone, keyboardType: TextInputType.phone),
                      const SizedBox(height: 16),

                      // Selección de Vehículo
                      const Text(
                        'Tipo de Vehículo',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black54),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: selectedVehicleType,
                        dropdownColor: Colors.white,
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                          prefixIcon: const Icon(Icons.commute, size: 18),
                        ),
                        style: const TextStyle(fontSize: 13, color: Colors.black87),
                        items: const [
                          DropdownMenuItem(value: 'Motocicleta', child: Text('Motocicleta')),
                          DropdownMenuItem(value: 'Automóvil', child: Text('Automóvil')),
                          DropdownMenuItem(value: 'Bicicleta', child: Text('Bicicleta')),
                          DropdownMenuItem(value: 'Camioneta', child: Text('Camioneta')),
                          DropdownMenuItem(value: 'A pie', child: Text('A pie')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setDialogState(() {
                              selectedVehicleType = val;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _buildDialogField(_vehicleController, 'Modelo del Vehículo (ej. Cargo 150)', Icons.motorcycle),
                      const SizedBox(height: 12),
                      _buildDialogField(_plateController, 'Placa (ej. FHJ-429)', Icons.credit_card),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.black54)),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (_formKey.currentState!.validate()) {
                            setDialogState(() => isSaving = true);
                            try {
                              final authService = Provider.of<AuthService>(context, listen: false);
                              final fullVehicleDescription = '$selectedVehicleType - ${_vehicleController.text.trim()}';
                              
                              await authService.updateDriverDetails(
                                driver.uid,
                                name: _nameController.text.trim(),
                                phone: _phoneController.text.trim(),
                                vehicle: fullVehicleDescription,
                                plate: _plateController.text.trim(),
                                photoUrl: selectedPhotoUrl,
                              );

                              if (mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Repartidor actualizado correctamente'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              setDialogState(() {
                                _errorMessage = 'Error: $e';
                              });
                            } finally {
                              setDialogState(() => isSaving = false);
                            }
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Guardar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildDialogField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool obscure = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.black87, fontSize: 14),
      validator: (val) => val == null || val.isEmpty ? 'Este campo es requerido' : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.black54, fontSize: 13),
        prefixIcon: Icon(icon, color: const Color(0xFF64748B), size: 18),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
    );
  }

  Widget _buildDriversTab() {
    final authService = Provider.of<AuthService>(context, listen: false);
    return StreamBuilder<List<Driver>>(
      stream: authService.getDriversStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final drivers = snapshot.data ?? [];
        
        return Column(
          children: [
            // Botón de registro intuitivo superior
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: ElevatedButton.icon(
                onPressed: _showAddDriverDialog,
                icon: const Icon(Icons.person_add_rounded, color: Colors.white, size: 20),
                label: const Text(
                  'REGISTRAR NUEVO REPARTIDOR',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  elevation: 0,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            
            Expanded(
              child: drivers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.people_outline, size: 64, color: Color(0xFF94A3B8)),
                          SizedBox(height: 16),
                          Text(
                            'No hay repartidores registrados',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black54),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: drivers.length,
                      itemBuilder: (context, index) {
                        final driver = drivers[index];
                        Color statusColor;
                        switch (driver.status) {
                          case 'available':
                            statusColor = Colors.green;
                            break;
                          case 'busy':
                            statusColor = Colors.orange;
                            break;
                          default:
                            statusColor = Colors.grey;
                        }

                        return Card(
                          color: Colors.white,
                          surfaceTintColor: Colors.white,
                          elevation: 0,
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: statusColor.withOpacity(0.1),
                                  backgroundImage: driver.photoUrl.isNotEmpty ? NetworkImage(driver.photoUrl) : null,
                                  child: driver.photoUrl.isEmpty ? Icon(Icons.electric_moped, color: statusColor, size: 20) : null,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        driver.name,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(driver.email, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Vehículo: ${driver.vehicle} (${driver.plate})',
                                        style: const TextStyle(color: Colors.black54, fontSize: 12),
                                      ),
                                      const SizedBox(height: 2),
                                      Text('Tel: ${driver.phone}', style: const TextStyle(color: Colors.black45, fontSize: 12)),
                                    ],
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: statusColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.circle, size: 6, color: statusColor),
                                          const SizedBox(width: 6),
                                          Text(
                                            driver.statusLabel,
                                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.edit_outlined, color: Colors.blueAccent, size: 20),
                                          onPressed: () => _showEditDriverDialog(driver),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text('Eliminar Repartidor'),
                                                content: Text('¿Estás seguro de que deseas eliminar a ${driver.name}?'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(context),
                                                    child: const Text('Cancelar'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () async {
                                                      Navigator.pop(context);
                                                      await authService.deleteDriver(driver.uid);
                                                      if (mounted) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          const SnackBar(content: Text('Repartidor eliminado')),
                                                        );
                                                      }
                                                    },
                                                    child: const Text('Eliminar', style: TextStyle(color: Colors.redAccent)),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildOrdersTab() {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    final authService = Provider.of<AuthService>(context, listen: false);

    return StreamBuilder<List<Order>>(
      stream: firestoreService.getOrdersStream(),
      builder: (context, ordersSnap) {
        if (ordersSnap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = ordersSnap.data ?? [];

        return StreamBuilder<List<Driver>>(
          stream: authService.getDriversStream(),
          builder: (context, driversSnap) {
            final drivers = driversSnap.data ?? [];

            return Column(
              children: [
                // Botón de registro de paquete intuitivo superior
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: ElevatedButton.icon(
                    onPressed: _showCreateOrderDialog,
                    icon: const Icon(Icons.inventory_2_rounded, color: Colors.white, size: 20),
                    label: const Text(
                      'REGISTRAR NUEVO PAQUETE',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, letterSpacing: 0.5, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      elevation: 0,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),

                Expanded(
                  child: orders.isEmpty
                      ? const Center(
                          child: Text(
                            'No hay pedidos registrados en el sistema.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: orders.length,
                          itemBuilder: (context, index) {
                            final order = orders[index];
                            final isAssigned = order.driverId.isNotEmpty;

                            return Card(
                              color: Colors.white,
                              surfaceTintColor: Colors.white,
                              elevation: 0,
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
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
                                            fontSize: 13,
                                            color: _getBrandColorStatic(order.brand),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: order.status == 'delivered'
                                                ? Colors.green.withOpacity(0.1)
                                                : (order.status == 'pending' ? Colors.blue.withOpacity(0.1) : Colors.orange.withOpacity(0.1)),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            order.status == 'pending' ? 'PENDIENTE' : order.status.toUpperCase(),
                                            style: TextStyle(
                                              color: order.status == 'delivered'
                                                  ? Colors.green
                                                  : (order.status == 'pending' ? Colors.blue : Colors.orange),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 9,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Pedido: #${order.id.split('-').last.toUpperCase()}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.black87),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                          tooltip: 'Eliminar Pedido',
                                          onPressed: () {
                                            showDialog(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text('Eliminar Pedido', style: TextStyle(fontWeight: FontWeight.bold)),
                                                content: Text('¿Estás seguro de que deseas eliminar permanentemente el pedido #${order.id.split('-').last.toUpperCase()}?'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(ctx),
                                                    child: const Text('Cancelar', style: TextStyle(color: Colors.black54)),
                                                  ),
                                                  ElevatedButton(
                                                    onPressed: () async {
                                                      Navigator.pop(ctx);
                                                      await firestoreService.deleteOrder(order.id);
                                                      if (context.mounted) {
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          const SnackBar(
                                                            content: Text('Pedido eliminado permanentemente.'),
                                                            backgroundColor: Colors.redAccent,
                                                          ),
                                                        );
                                                      }
                                                    },
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                                    child: const Text('Eliminar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text('Producto: ${order.item}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                    Text('Cliente: ${order.client}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                                    const SizedBox(height: 12),
                                    const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                    const SizedBox(height: 12),
                                    if (isAssigned) ...[
                                      Row(
                                        children: [
                                          const Icon(Icons.electric_moped, size: 16, color: Colors.blueGrey),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              'Asignado a: ${order.driverName} (${order.driverVehicle})',
                                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.blueGrey),
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (order.status != 'delivered' && order.status != 'pending') ...[
                                        const SizedBox(height: 8),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(4),
                                          child: LinearProgressIndicator(
                                            value: order.progress / 100.0,
                                            backgroundColor: Color(0xFFF1F5F9),
                                            valueColor: AlwaysStoppedAnimation<Color>(_getBrandColorStatic(order.brand)),
                                            minHeight: 4,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Progreso: ${order.progress.toStringAsFixed(0)}% | ETA: ${order.eta} min',
                                          style: const TextStyle(fontSize: 10, color: Colors.black38),
                                        ),
                                      ],
                                    ] else ...[
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text(
                                            'Sin repartidor asignado',
                                            style: TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w500),
                                          ),
                                          if (drivers.isNotEmpty)
                                            ElevatedButton(
                                              onPressed: () {
                                                _showAssignDriverDialog(order, drivers, firestoreService);
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF3B82F6),
                                                foregroundColor: Colors.white,
                                                elevation: 0,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                              ),
                                              child: const Text('Asignar Repartidor', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                            )
                                          else
                                            const Text(
                                              '(Registra repartidores primero)',
                                              style: TextStyle(fontSize: 11, color: Colors.black38),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAssignDriverDialog(Order order, List<Driver> drivers, FirestoreService service) {
    Driver? selectedDriver = drivers.firstWhere((d) => d.status == 'available', orElse: () => drivers.first);
    
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                'Asignar Repartidor',
                style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Selecciona un repartidor para la orden #${order.id.split('-').last.toUpperCase()}:',
                    style: const TextStyle(fontSize: 13, color: Colors.black54),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<Driver>(
                    value: selectedDriver,
                    dropdownColor: Colors.white,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    isExpanded: true,
                    items: drivers.map((driver) {
                      Color statusColor;
                      switch (driver.status) {
                        case 'available':
                          statusColor = Colors.green;
                          break;
                        case 'busy':
                          statusColor = Colors.orange;
                          break;
                        default:
                          statusColor = Colors.grey;
                      }
                      return DropdownMenuItem<Driver>(
                        value: driver,
                        child: Row(
                          children: [
                            Icon(Icons.circle, size: 8, color: statusColor),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${driver.name} (${driver.vehicle})',
                                style: const TextStyle(fontSize: 13, color: Colors.black87),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedDriver = val);
                      }
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar', style: TextStyle(color: Colors.black54)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (selectedDriver != null) {
                      Navigator.pop(context);
                      await service.assignDriverToOrder(
                        order.id,
                        driverId: selectedDriver!.uid,
                        driverName: selectedDriver!.name,
                        driverVehicle: '${selectedDriver!.vehicle} (${selectedDriver!.plate})',
                      );
                      
                      final authService = Provider.of<AuthService>(context, listen: false);
                      await authService.updateDriverStatus(selectedDriver!.uid, 'busy');

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Orden asignada a ${selectedDriver!.name}'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Confirmar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // DIÁLOGO DE CREACIÓN DE PAQUETE CON ESCÁNER
  // ---------------------------------------------------------------------------
  void _showCreateOrderDialog() {
    final itemController = TextEditingController();
    final trackingController = TextEditingController();
    final clientEmailController = TextEditingController();
    final addressController = TextEditingController(text: 'Calle Juárez #123, Centro');

    String selectedBrand = 'Amazon Prime';
    String? foundClientName;
    String? foundClientId;
    String? orderError;
    bool isSearching = false;

    final brands = ['Amazon Prime', 'MercadoLibre', 'DHL Express', 'FedEx', 'Estafeta', 'UPS', 'Otro'];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.inventory_2_rounded, color: Color(0xFF3B82F6), size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Registrar Paquete',
                    style: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (orderError != null)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
                        ),
                        child: Text(orderError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                      ),

                    // ── Escáner de código de barras ──
                    const Text('Código de Rastreo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: trackingController,
                            style: const TextStyle(fontSize: 14, color: Colors.black87),
                            decoration: InputDecoration(
                              hintText: 'Ej: AMZ-2024-001',
                              hintStyle: const TextStyle(color: Colors.black26),
                              filled: true,
                              fillColor: const Color(0xFFF1F5F9),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: const Color(0xFF3B82F6),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => _BarcodeScannerScreen(
                                    onScanned: (code) {
                                      setDialogState(() {
                                        trackingController.text = code;
                                        if (itemController.text.isEmpty) {
                                          itemController.text = 'Paquete $code';
                                        }
                                      });
                                    },
                                  ),
                                ),
                              );
                            },
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 22),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Nombre del producto ──
                    const Text('Producto', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: itemController,
                      style: const TextStyle(fontSize: 14, color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Ej: Audífonos Bluetooth',
                        hintStyle: const TextStyle(color: Colors.black26),
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── Paquetería ──
                    const Text('Paquetería', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedBrand,
                      dropdownColor: Colors.white,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      items: brands.map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontSize: 14)))).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedBrand = val);
                      },
                    ),

                    const SizedBox(height: 16),

                    // ── Dirección descriptiva ──
                    const Text('Dirección de Entrega', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: addressController,
                      style: const TextStyle(fontSize: 14, color: Colors.black87),
                      decoration: InputDecoration(
                        hintText: 'Ej: Calle Juárez #123, Centro',
                        hintStyle: const TextStyle(color: Colors.black26),
                        filled: true,
                        fillColor: const Color(0xFFF1F5F9),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),

                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),

                    // ── Buscar cliente por correo ──
                    const Text('Correo del Cliente (dueño)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black54)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: clientEmailController,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(fontSize: 14, color: Colors.black87),
                            decoration: InputDecoration(
                              hintText: 'ejemplo@correo.com',
                              hintStyle: const TextStyle(color: Colors.black26),
                              filled: true,
                              fillColor: const Color(0xFFF1F5F9),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              prefixIcon: const Icon(Icons.email_outlined, size: 18, color: Colors.black38),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Material(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: isSearching ? null : () async {
                              final email = clientEmailController.text.trim();
                              if (email.isEmpty) {
                                setDialogState(() => orderError = 'Ingresa un correo para buscar al cliente.');
                                return;
                              }
                              setDialogState(() {
                                isSearching = true;
                                orderError = null;
                                foundClientName = null;
                                foundClientId = null;
                              });
                              try {
                                final authService = Provider.of<AuthService>(context, listen: false);
                                final user = await authService.findUserByEmail(email);
                                setDialogState(() {
                                  isSearching = false;
                                  if (user != null) {
                                    foundClientName = user.name;
                                    foundClientId = user.uid;
                                    orderError = null;
                                  } else {
                                    orderError = 'No se encontró ningún usuario con ese correo.';
                                  }
                                });
                              } catch (e) {
                                setDialogState(() {
                                  isSearching = false;
                                  orderError = 'Error buscando el cliente.';
                                });
                              }
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: isSearching
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Icon(Icons.search_rounded, color: Colors.white, size: 22),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // ── Resultado de búsqueda ──
                    if (foundClientName != null)
                      Container(
                        margin: const EdgeInsets.only(top: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFBBF7D0)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Color(0xFF16A34A), size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    foundClientName!,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF166534)),
                                  ),
                                  Text(
                                    clientEmailController.text.trim(),
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF4ADE80)),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: const Text('Cancelar', style: TextStyle(color: Colors.black54)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (itemController.text.trim().isEmpty) {
                      setDialogState(() => orderError = 'Ingresa el nombre del producto.');
                      return;
                    }
                    if (foundClientId == null) {
                      setDialogState(() => orderError = 'Primero busca y vincula al cliente por correo.');
                      return;
                    }

                    // Coordenadas fijas por defecto por ser más sencillas y transparentes
                    const double lat = 20.3700;
                    const double lng = -100.0150;

                    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
                    await firestoreService.createOrder(
                      item: '${itemController.text.trim()} (${addressController.text.trim()})',
                      clientId: foundClientId!,
                      clientName: foundClientName!,
                      brand: selectedBrand,
                      trackingNumber: trackingController.text.trim(),
                      destLatitude: lat,
                      destLongitude: lng,
                    );

                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Paquete registrado y asignado a ${foundClientName!}'),
                          backgroundColor: const Color(0xFF10B981),
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Crear Paquete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Panel de Administración',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black87),
        ),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFF3B82F6),
          unselectedLabelColor: Colors.black38,
          indicatorColor: const Color(0xFF3B82F6),
          indicatorSize: TabBarIndicatorSize.tab,
          tabs: const [
            Tab(icon: Icon(Icons.people_outline, size: 20), text: 'Repartidores'),
            Tab(icon: Icon(Icons.receipt_long_outlined, size: 20), text: 'Pedidos'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.redAccent, size: 20),
            tooltip: 'Cerrar Sesión',
            onPressed: () => authService.signOut(),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDriversTab(),
          _buildOrdersTab(),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// PANTALLA DE ESCÁNER DE CÓDIGO DE BARRAS
// ----------------------------------------------------------------------------
class _BarcodeScannerScreen extends StatefulWidget {
  final Function(String) onScanned;
  const _BarcodeScannerScreen({required this.onScanned});

  @override
  State<_BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<_BarcodeScannerScreen> {
  bool _hasScanned = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Escanear Código de Barras', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        elevation: 0,
      ),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              if (_hasScanned) return;
              final List<Barcode> barcodes = capture.barcodes;
              if (barcodes.isNotEmpty && barcodes.first.rawValue != null) {
                _hasScanned = true;
                final code = barcodes.first.rawValue!;
                widget.onScanned(code);
                Navigator.pop(context);
              }
            },
          ),
          // Overlay con guía visual
          Center(
            child: Container(
              width: 280,
              height: 140,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF3B82F6), width: 2.5),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Apunta al código de barras del paquete',
                    style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// WIDGET GLOBAL DE NOTIFICACIONES IN-APP EN TIEMPO REAL
// ----------------------------------------------------------------------------
class InAppNotificationOverlay extends StatefulWidget {
  final Widget child;
  final String userEmail;
  final String userId;
  final String userRole;

  const InAppNotificationOverlay({
    super.key,
    required this.child,
    required this.userEmail,
    required this.userId,
    this.userRole = 'client',
  });

  @override
  State<InAppNotificationOverlay> createState() => _InAppNotificationOverlayState();
}

class _InAppNotificationOverlayState extends State<InAppNotificationOverlay> {
  StreamSubscription<List<Order>>? _ordersSubscription;
  final Map<String, String> _previousOrderStatuses = {};
  OverlayEntry? _currentOverlay;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _startListeningToOrders();
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _dismissTimer?.cancel();
    _removeCurrentNotification();
    super.dispose();
  }

  void _startListeningToOrders() {
    final firestoreService = Provider.of<FirestoreService>(context, listen: false);
    // Usar stream filtrado según el rol del usuario
    final stream = widget.userRole == 'driver'
        ? firestoreService.getOrdersForDriver(widget.userId)
        : firestoreService.getOrdersForClient(widget.userId);

    _ordersSubscription = stream.listen((orders) {
      final settings = Provider.of<AppSettings>(context, listen: false);
      for (final order in orders) {
        final String? prevStatus = _previousOrderStatuses[order.id];
        if (prevStatus != null && prevStatus != order.status) {
          if (settings.receiveNotifications) {
            _showNotification(order);
          }
        }
        _previousOrderStatuses[order.id] = order.status;
      }
    });
  }

  void _removeCurrentNotification() {
    if (_currentOverlay != null) {
      _currentOverlay!.remove();
      _currentOverlay = null;
    }
  }

  void _showNotification(Order order) {
    _dismissTimer?.cancel();
    _removeCurrentNotification();

    String title = '';
    String description = '';
    IconData icon = Icons.notifications;
    Color color = Colors.blue;

    switch (order.status) {
      case 'accepted':
        title = '¡Pedido Aceptado!';
        description = '${order.driverName} aceptó entregar tu paquete de ${order.brand}.';
        icon = Icons.assignment_turned_in_rounded;
        color = Colors.indigo;
        break;
      case 'in_transit':
        title = 'Paquete en Camino 🏍️';
        description = 'Tu paquete de ${order.item} ya va en camino a tu ubicación.';
        icon = Icons.motorcycle_rounded;
        color = const Color(0xFF2563EB);
        break;
      case 'arrived':
        title = '¡El repartidor ha llegado! 📍';
        description = 'Sal a recibir a ${order.driverName}. Ten listo tu código: ${order.passcode}';
        icon = Icons.pin_drop_rounded;
        color = Colors.amber.shade800;
        break;
      case 'delivered':
        title = '¡Entrega Exitosa! 🎉';
        description = 'Tu paquete de ${order.brand} ha sido entregado correctamente.';
        icon = Icons.done_all_rounded;
        color = Colors.green;
        break;
    }

    _currentOverlay = OverlayEntry(
      builder: (context) {
        return Positioned(
          top: 24,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 4)),
                ],
                border: Border.all(color: color.withOpacity(0.2), width: 1.5),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withOpacity(0.1),
                    child: Icon(icon, color: color, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          style: const TextStyle(fontSize: 10, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Colors.grey),
                    onPressed: _removeCurrentNotification,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_currentOverlay!);

    // Descartar automáticamente después de 5 segundos
    _dismissTimer = Timer(const Duration(seconds: 5), () {
      _removeCurrentNotification();
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
