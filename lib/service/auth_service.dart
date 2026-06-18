// lib/service/auth_service.dart
// UPDATED: adminCreateUser menerima faskesId & faskesName untuk role petugas
// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import '../models/user_models.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final List<String> _adminEmails = [
    'rafiputraadipratama4@gmail.com',
    'campgreget@gmail.com',
  ];

  static const String _webApiKey = 'AIzaSyBQ8_dBqeNOanvnptDBE3AMlE5X4SENT1g';

  // ═══════════════════════════════════════════════════════════════
  // LOGIN DENGAN EMAIL & PASSWORD
  // ═══════════════════════════════════════════════════════════════
  Future<UserModel?> signInWithEmail(String email, String password) async {
    try {
      final UserCredential result = await _auth.signInWithEmailAndPassword(
        email: email, password: password);
      final User? user = result.user;
      if (user == null) return null;
      return await getUserData(user.uid);
    } catch (e) {
      print('Error login: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // REGISTER DENGAN EMAIL & PASSWORD (self-register)
  // ═══════════════════════════════════════════════════════════════
  Future<UserModel?> registerWithEmail(
      String email, String password, String name) async {
    try {
      final UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email, password: password);
      final User? user = result.user;
      if (user == null) return null;
      final String role = _adminEmails.contains(email) ? 'admin' : 'user';
      final newUser = UserModel(
        uid: user.uid, email: email, name: name, photoUrl: '',
        role: role, createdAt: DateTime.now());
      await _firestore.collection('users').doc(user.uid).set(newUser.toMap());
      await user.updateDisplayName(name);
      await user.reload();
      return newUser;
    } catch (e) {
      print('Error register: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // REGISTER DENGAN GOOGLE (dari halaman Signup)
  // ═══════════════════════════════════════════════════════════════
  Future<GoogleAuthResult> registerWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return GoogleAuthResult.cancelled();
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
      final UserCredential result = await _auth.signInWithCredential(credential);
      final User? user = result.user;
      if (user == null) return GoogleAuthResult.error('Gagal mendapatkan data akun.');
      final googleEmail = (user.email ?? '').toLowerCase();
      final emailQuery = await _firestore.collection('users')
          .where('email', isEqualTo: googleEmail).limit(1).get();
      if (emailQuery.docs.isNotEmpty) {
        await _auth.signOut();
        await _googleSignIn.signOut();
        return GoogleAuthResult.alreadyExists();
      }
      final finalRole = _adminEmails.contains(user.email) ? 'admin' : 'user';
      final newUser = UserModel(
        uid: user.uid, email: googleEmail,
        name: user.displayName ?? 'User', photoUrl: user.photoURL ?? '',
        role: finalRole, createdAt: DateTime.now());
      await _firestore.collection('users').doc(user.uid).set(newUser.toMap());
      print('[AUTH] ✅ Google register: ${user.uid} $googleEmail');
      return GoogleAuthResult.success(newUser);
    } catch (e) {
      print('Error Google register: $e');
      return GoogleAuthResult.error('Terjadi kesalahan: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // LOGIN DENGAN GOOGLE (dari halaman Login)
  // ═══════════════════════════════════════════════════════════════
  Future<GoogleAuthResult> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return GoogleAuthResult.cancelled();
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken, idToken: googleAuth.idToken);
      final UserCredential result = await _auth.signInWithCredential(credential);
      final User? user = result.user;
      if (user == null) return GoogleAuthResult.error('Gagal mendapatkan data akun.');
      final googleEmail = (user.email ?? '').toLowerCase();
      final docSnap = await _firestore.collection('users').doc(user.uid).get();
      if (docSnap.exists) {
        final userData = await getUserData(user.uid);
        if (userData == null) {
          await _auth.signOut();
          await _googleSignIn.signOut();
          return GoogleAuthResult.notRegistered();
        }
        return GoogleAuthResult.success(userData);
      }
      final emailQuery = await _firestore.collection('users')
          .where('email', isEqualTo: googleEmail).limit(1).get();
      if (emailQuery.docs.isEmpty) {
        await _auth.signOut();
        await _googleSignIn.signOut();
        return GoogleAuthResult.notRegistered();
      }
      final oldDoc  = emailQuery.docs.first;
      final oldData = oldDoc.data();
      final migratedUser = UserModel(
        uid: user.uid,
        email: oldData['email'] ?? googleEmail,
        name: oldData['name'] ?? user.displayName ?? 'User',
        photoUrl: user.photoURL ?? oldData['photoUrl'] ?? '',
        role: oldData['role'] ?? 'user',
        createdAt: (oldData['createdAt'] is Timestamp)
            ? (oldData['createdAt'] as Timestamp).toDate() : DateTime.now(),
      );
      await _firestore.collection('users').doc(user.uid).set(migratedUser.toMap());
      if (oldDoc.id != user.uid) {
        await _firestore.collection('users').doc(oldDoc.id).delete();
        print('[AUTH] 🔄 Migrasi: ${oldDoc.id} → ${user.uid}');
      }
      return GoogleAuthResult.success(migratedUser);
    } catch (e) {
      print('Error Google Sign-In: $e');
      return GoogleAuthResult.error('Terjadi kesalahan: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // CREATE USER OLEH ADMIN (REST API)
  // UPDATED: terima faskesId & faskesName untuk petugas
  // ═══════════════════════════════════════════════════════════════
  Future<AdminCreateUserResult> adminCreateUser({
    required String name,
    required String email,
    required String password,
    required String role,
    String? faskesId,    // ← NEW
    String? faskesName,  // ← NEW
  }) async {
    final trimEmail = email.trim().toLowerCase();
    final trimName  = name.trim();
    try {
      final existingQuery = await _firestore.collection('users')
          .where('email', isEqualTo: trimEmail).limit(1).get();
      if (existingQuery.docs.isNotEmpty) {
        return AdminCreateUserResult.error('Email "$trimEmail" sudah terdaftar di sistem.');
      }
      final url = Uri.parse(
          'https://identitytoolkit.googleapis.com/v1/accounts:signUp?key=$_webApiKey');
      final resp = await http.post(url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email': trimEmail, 'password': password,
          'displayName': trimName, 'returnSecureToken': true,
        }),
      );
      if (resp.statusCode != 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        final msg  = ((body['error'] as Map?)?['message'] as String?) ?? 'Gagal membuat akun';
        return AdminCreateUserResult.error(_translateFirebaseError(msg));
      }
      final body      = jsonDecode(resp.body) as Map<String, dynamic>;
      final uid       = body['localId'] as String;
      final finalRole = _adminEmails.contains(trimEmail) ? 'admin' : role;

      // Simpan ke Firestore, termasuk faskesId & faskesName jika petugas
      final userData = <String, dynamic>{
        'uid': uid, 'email': trimEmail, 'name': trimName, 'photoUrl': '',
        'role': finalRole, 'createdAt': DateTime.now(),
      };
      if (finalRole == 'petugas' && faskesId != null) {
        userData['faskesId']   = faskesId;
        userData['faskesName'] = faskesName ?? '';
      }
      await _firestore.collection('users').doc(uid).set(userData);

      final newUser = UserModel(
        uid: uid, email: trimEmail, name: trimName,
        photoUrl: '', role: finalRole, createdAt: DateTime.now());
      print('[AUTH] ✅ Admin created: $trimEmail ($finalRole) uid=$uid'
          '${faskesName != null ? ' faskes=$faskesName' : ''}');
      return AdminCreateUserResult.success(newUser);
    } catch (e) {
      print('[AUTH] adminCreateUser error: $e');
      return AdminCreateUserResult.error('Terjadi kesalahan: $e');
    }
  }

  String _translateFirebaseError(String code) {
    if (code.contains('WEAK_PASSWORD')) return 'Password terlalu lemah (minimal 6 karakter).';
    switch (code) {
      case 'EMAIL_EXISTS':          return 'Email sudah digunakan oleh akun lain.';
      case 'INVALID_EMAIL':         return 'Format email tidak valid.';
      case 'OPERATION_NOT_ALLOWED': return 'Metode email/password belum diaktifkan di Firebase Console.';
      case 'TOO_MANY_ATTEMPTS_TRY_LATER': return 'Terlalu banyak percobaan. Coba lagi nanti.';
      default:                      return code;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // GET USER DATA / SIGN OUT
  // ═══════════════════════════════════════════════════════════════
  Future<UserModel?> getUserData(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) return UserModel.fromMap(doc.data()!);
      return null;
    } catch (e) {
      print('Error get user data: $e');
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _auth.signOut();
    } catch (e) {
      print('Error sign out: $e');
    }
  }

  User? getCurrentUser() => _auth.currentUser;
  Stream<User?> authStateChanges() => _auth.authStateChanges();
}

// ─────────────────────────────────────────────────────────────────────
// Result models
// ─────────────────────────────────────────────────────────────────────
enum GoogleAuthStatus { success, cancelled, notRegistered, alreadyExists, error }

class GoogleAuthResult {
  final GoogleAuthStatus status;
  final UserModel? user;
  final String? errorMessage;
  const GoogleAuthResult._({required this.status, this.user, this.errorMessage});
  factory GoogleAuthResult.success(UserModel user) =>
      GoogleAuthResult._(status: GoogleAuthStatus.success, user: user);
  factory GoogleAuthResult.cancelled() =>
      GoogleAuthResult._(status: GoogleAuthStatus.cancelled);
  factory GoogleAuthResult.notRegistered() =>
      GoogleAuthResult._(status: GoogleAuthStatus.notRegistered);
  factory GoogleAuthResult.alreadyExists() =>
      GoogleAuthResult._(status: GoogleAuthStatus.alreadyExists);
  factory GoogleAuthResult.error(String message) =>
      GoogleAuthResult._(status: GoogleAuthStatus.error, errorMessage: message);
  bool get isSuccess => status == GoogleAuthStatus.success;
}

class AdminCreateUserResult {
  final bool isSuccess;
  final UserModel? user;
  final String? errorMessage;
  const AdminCreateUserResult._({required this.isSuccess, this.user, this.errorMessage});
  factory AdminCreateUserResult.success(UserModel user) =>
      AdminCreateUserResult._(isSuccess: true, user: user);
  factory AdminCreateUserResult.error(String message) =>
      AdminCreateUserResult._(isSuccess: false, errorMessage: message);
}