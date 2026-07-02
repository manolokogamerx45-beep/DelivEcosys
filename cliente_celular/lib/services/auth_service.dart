import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../models/app_user.dart';
import '../models/driver.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Email del administrador principal
  static const String adminEmail = 'danielgs.ti23@utsjr.edu.mx';

  // Stream del estado de autenticación
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Usuario actual de Firebase
  User? get currentFirebaseUser => _auth.currentUser;

  // ---------------------------------------------------------------------------
  // LOGIN
  // ---------------------------------------------------------------------------
  Future<AppUser> signIn(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final user = credential.user!;
    return await _getOrCreateUserDoc(user);
  }

  // REGISTRO DE NUEVO CLIENTE (CORREO Y CONTRASEÑA)
  Future<AppUser> registerWithEmail({
    required String name,
    required String email,
    required String password,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = credential.user!;
    
    // El rol por defecto siempre es cliente para registros directos
    final appUser = AppUser(
      uid: user.uid,
      email: user.email!,
      name: name,
      role: 'client',
    );
    
    await _db.collection('users').doc(user.uid).set(appUser.toMap());
    return appUser;
  }

  // Google Sign-In
  Future<AppUser?> signInWithGoogle() async {
    final GoogleSignIn googleSignIn = GoogleSignIn();
    final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      return null; // El usuario canceló el flujo de login
    }

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final AuthCredential credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await _auth.signInWithCredential(credential);
    final user = userCredential.user;
    if (user == null) return null;

    return await _getOrCreateUserDoc(user);
  }

  // ---------------------------------------------------------------------------
  // RECUPERAR CONTRASEÑA
  // ---------------------------------------------------------------------------
  Future<void> sendPasswordResetEmail(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  // ---------------------------------------------------------------------------
  // BUSCAR USUARIO POR CORREO (para vincular paquetes)
  // ---------------------------------------------------------------------------
  Future<AppUser?> findUserByEmail(String email) async {
    final query = await _db
        .collection('users')
        .where('email', isEqualTo: email.trim().toLowerCase())
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      // Intentar sin toLowerCase por si el email se guardó con mayúsculas
      final query2 = await _db
          .collection('users')
          .where('email', isEqualTo: email.trim())
          .limit(1)
          .get();
      if (query2.docs.isEmpty) return null;
      return AppUser.fromMap(query2.docs.first.id, query2.docs.first.data());
    }

    return AppUser.fromMap(query.docs.first.id, query.docs.first.data());
  }

  // ---------------------------------------------------------------------------
  // LOGOUT
  // ---------------------------------------------------------------------------
  Future<void> signOut() async {
    await _auth.signOut();
  }

  // ---------------------------------------------------------------------------
  // Obtener o crear documento de usuario en Firestore
  // ---------------------------------------------------------------------------
  Future<AppUser> _getOrCreateUserDoc(User firebaseUser) async {
    final docRef = _db.collection('users').doc(firebaseUser.uid);
    final docSnap = await docRef.get();

    if (docSnap.exists) {
      return AppUser.fromMap(firebaseUser.uid, docSnap.data()!);
    }

    // Primera vez: determinar rol por email
    final role = firebaseUser.email == adminEmail ? 'admin' : 'client';
    final name = firebaseUser.displayName ?? firebaseUser.email!.split('@').first;

    final appUser = AppUser(
      uid: firebaseUser.uid,
      email: firebaseUser.email!,
      name: name,
      role: role,
    );

    await docRef.set(appUser.toMap());
    return appUser;
  }

  // ---------------------------------------------------------------------------
  // Obtener AppUser del usuario actual
  // ---------------------------------------------------------------------------
  Future<AppUser?> getCurrentAppUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;

    final docSnap = await _db.collection('users').doc(firebaseUser.uid).get();
    if (!docSnap.exists) return null;

    return AppUser.fromMap(firebaseUser.uid, docSnap.data()!);
  }

  // ---------------------------------------------------------------------------
  // CREAR REPARTIDOR (solo admin)
  // ---------------------------------------------------------------------------
  Future<void> createDriver({
    required String name,
    required String email,
    required String password,
    required String phone,
    required String vehicle,
    required String plate,
    String photoUrl = '',
  }) async {
    // Inicializar una app de Firebase secundaria para registrar al usuario
    // sin desloguear al administrador actual
    final secondaryApp = await Firebase.initializeApp(
      name: 'SecondaryDriverRegister',
      options: Firebase.app().options,
    );
    final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
    
    // Crear el usuario repartidor
    final credential = await secondaryAuth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final driverUid = credential.user!.uid;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Crear documento en users/
    await _db.collection('users').doc(driverUid).set({
      'email': email.trim(),
      'name': name,
      'role': 'driver',
      'createdAt': now,
    });

    // Crear documento en drivers/
    final driver = Driver(
      uid: driverUid,
      name: name,
      email: email.trim(),
      phone: phone,
      vehicle: vehicle,
      plate: plate,
      status: 'offline',
      active: true,
      createdAt: now,
      photoUrl: photoUrl,
    );

    await _db.collection('drivers').doc(driverUid).set(driver.toMap());

    // Eliminar la app secundaria para liberar recursos
    await secondaryApp.delete();
  }

  // ---------------------------------------------------------------------------
  // Stream de repartidores (para admin)
  // ---------------------------------------------------------------------------
  Stream<List<Driver>> getDriversStream() {
    return _db
        .collection('drivers')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => Driver.fromMap(doc.id, doc.data()))
            .toList());
  }

  // ---------------------------------------------------------------------------
  // Actualizar estado del repartidor
  // ---------------------------------------------------------------------------
  Future<void> updateDriverStatus(String uid, String status) async {
    await _db.collection('drivers').doc(uid).update({'status': status});
  }

  // Actualizar datos del repartidor (Admin)
  Future<void> updateDriverDetails(
    String uid, {
    required String name,
    required String phone,
    required String vehicle,
    required String plate,
    required String photoUrl,
  }) async {
    await _db.collection('drivers').doc(uid).update({
      'name': name,
      'phone': phone,
      'vehicle': vehicle,
      'plate': plate,
      'photoUrl': photoUrl,
    });
    await _db.collection('users').doc(uid).update({
      'name': name,
    });
  }

  // ---------------------------------------------------------------------------
  // Eliminar repartidor
  // ---------------------------------------------------------------------------
  Future<void> deleteDriver(String uid) async {
    await _db.collection('drivers').doc(uid).delete();
    await _db.collection('users').doc(uid).delete();
  }

  // ---------------------------------------------------------------------------
  // Traducir errores de Firebase Auth al español
  // ---------------------------------------------------------------------------
  String getErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'No existe una cuenta con ese correo.';
      case 'wrong-password':
        return 'Contraseña incorrecta.';
      case 'invalid-email':
        return 'El correo no tiene un formato válido.';
      case 'user-disabled':
        return 'Esta cuenta ha sido deshabilitada.';
      case 'too-many-requests':
        return 'Demasiados intentos. Espera un momento.';
      case 'email-already-in-use':
        return 'Este correo ya está registrado.';
      case 'weak-password':
        return 'La contraseña debe tener al menos 6 caracteres.';
      case 'invalid-credential':
        return 'Correo o contraseña incorrectos.';
      default:
        return 'Error: ${e.message}';
    }
  }
}
