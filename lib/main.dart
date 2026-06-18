// lib/main.dart
import 'package:flutter/material.dart';
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'service/auth_service.dart';
import 'service/notification_service.dart';
import 'models/user_models.dart';
import 'widgets/bottom_nav.dart';
import 'widgets/loading_widget.dart';
import 'screens/auth_screens.dart';
import 'screens/home_screen.dart';
import 'screens/user_screens.dart';
import 'screens/admin_screens.dart';
import 'screens/map_screen.dart';
import 'screens/petugas_screen.dart';
import 'screens/notification_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  await NotificationService().initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PSC 119 Event Medic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFC0392B),
          primary: const Color(0xFFC0392B),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF7F5F3),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Color(0xFF2C2520),
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFF2C2520),
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
          iconTheme: IconThemeData(color: Color(0xFF2C2520)),
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LoadingWidget(message: 'Memuat...');
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const MainAppController(isLoggedIn: false);
        }

        final firebaseUser = snapshot.data!;

        return FutureBuilder<UserModel?>(
          future: AuthService().getUserData(firebaseUser.uid),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const LoadingWidget(message: 'Memuat profil...');
            }
            if (userSnapshot.data == null) {
              AuthService().signOut();
              return const MainAppController(isLoggedIn: false);
            }

            final user = userSnapshot.data!;

            if (user.role == 'petugas') {
              return _PetugasEntryPoint(user: user);
            }

            return MainAppController(
              isLoggedIn: true,
              initialRole: user.role,
              loggedInUser: user,
            );
          },
        );
      },
    );
  }
}

class _PetugasEntryPoint extends StatefulWidget {
  final UserModel user;
  const _PetugasEntryPoint({required this.user});

  @override
  State<_PetugasEntryPoint> createState() => _PetugasEntryPointState();
}

class _PetugasEntryPointState extends State<_PetugasEntryPoint> {
  bool _loggingOut = false;

  Future<void> _handleLogout() async {
    setState(() => _loggingOut = true);
    await AuthService().signOut();
  }

  @override
  Widget build(BuildContext context) {
    if (_loggingOut) return const LoadingWidget(message: 'Keluar...');
    return PetugasHomeWrapper(
      petugasUser: widget.user,
      onLogout: _handleLogout,
    );
  }
}

class MainAppController extends StatefulWidget {
  final bool isLoggedIn;
  final String initialRole;
  final UserModel? loggedInUser;

  const MainAppController({
    super.key,
    this.isLoggedIn = false,
    this.initialRole = 'user',
    this.loggedInUser,
  });

  @override
  State<MainAppController> createState() => _MainAppControllerState();
}

class _MainAppControllerState extends State<MainAppController> {
  late String currentScreen;
  late String userRole;
  String bookingState = 'idle';
  UserModel? _currentUser;

  final List<String> _screenStack = [];

  List<Map<String, dynamic>> historyList    = [];
  List<Map<String, dynamic>> usersList      = [];
  List<Map<String, dynamic>> ambulancesList = [];

  String eventType = 'Konser';
  final TextEditingController _eventNameController = TextEditingController();
  final TextEditingController _eventDateController = TextEditingController();
  final TextEditingController _eventLocController  = TextEditingController();

  List<String> _uploadedDocNames = [];

  @override
  void initState() {
    super.initState();
    _currentUser = widget.loggedInUser;

    if (widget.isLoggedIn) {
      currentScreen = 'home';
      userRole = widget.initialRole;
      _screenStack.add('home');
    } else {
      currentScreen = 'welcome';
      userRole = 'user';
      _screenStack.add('welcome');
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && currentScreen == 'welcome') {
          _navigateTo('login');
        }
      });
    }
  }

  @override
  void dispose() {
    _eventNameController.dispose();
    _eventDateController.dispose();
    _eventLocController.dispose();
    super.dispose();
  }

  void _navigateTo(String screen) {
    setState(() {
      if (_screenStack.isEmpty || _screenStack.last != screen) {
        _screenStack.add(screen);
      }
      currentScreen = screen;
    });
  }

  bool _popScreen() {
    if (_screenStack.length > 1) {
      _screenStack.removeLast();
      final prev = _screenStack.last;
      setState(() => currentScreen = prev);
      return true;
    }
    return false;
  }

  void handleLogin(String role, {UserModel? user}) {
    setState(() {
      userRole = role;
      _currentUser = user;
      _screenStack.clear();
      _screenStack.add('home');
      currentScreen = 'home';
    });
  }

  void startBooking() => setState(() => bookingState = 'form');

  void confirmBooking() {
    setState(() {
      bookingState = 'searching';
      currentScreen = 'map';
    });
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          bookingState = 'booked';
          historyList.insert(0, {
            'id': DateTime.now().millisecondsSinceEpoch,
            'date': _eventDateController.text.isEmpty
                ? 'Hari Ini'
                : _eventDateController.text,
            'eventName': _eventNameController.text.isEmpty
                ? 'Event Baru'
                : _eventNameController.text,
            'type': eventType,
            'status': 'Menunggu Konfirmasi',
            'driver': '-',
            'plate': '-',
          });
        });
      }
    });
  }

  void cancelBooking() {
    if (bookingState == 'booked' && historyList.isNotEmpty) {
      if (historyList[0]['status'] == 'Menunggu Konfirmasi') {
        historyList[0]['status'] = 'Dibatalkan';
      }
    }
    setState(() {
      bookingState = 'idle';
      _eventNameController.clear();
      _eventDateController.clear();
      _eventLocController.clear();
      _uploadedDocNames = [];
      _screenStack.clear();
      _screenStack.add('home');
      currentScreen = 'home';
    });
  }

  void addUser(Map<String, dynamic> user) =>
      setState(() => usersList.add(user));
  void deleteUser(int id) =>
      setState(() => usersList.removeWhere((u) => u['id'] == id));
  void addAmbulance(Map<String, dynamic> amb) =>
      setState(() => ambulancesList.add(amb));
  void deleteAmbulance(int id) =>
      setState(() => ambulancesList.removeWhere((a) => a['id'] == id));

  void handleLogout() async {
    await AuthService().signOut();
    if (mounted) {
      setState(() {
        _screenStack.clear();
        _screenStack.add('welcome');
        currentScreen = 'welcome';
        bookingState  = 'idle';
        _currentUser  = null;
        userRole      = 'user';
      });
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && currentScreen == 'welcome') {
          _navigateTo('login');
        }
      });
    }
  }

  bool get _showBottomNav {
    if (currentScreen == 'home' && bookingState != 'idle') return false;
    return ['home', 'map', 'history', 'menu'].contains(currentScreen);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (bookingState == 'form') {
          setState(() => bookingState = 'idle');
          return;
        }
        if (_popScreen()) return;
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            _buildScreen(),
            if (_showBottomNav)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: SafeArea(
                  child: BottomNav(
                    currentScreen: currentScreen,
                    onTab: (screen) {
                      setState(() {
                        _screenStack.clear();
                        _screenStack.add(screen);
                        currentScreen = screen;
                      });
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScreen() {
    switch (currentScreen) {
      case 'welcome':
        return const WelcomeScreen();
      case 'login':
        return LoginScreen(
          onLogin: handleLogin,
          onToSignup: () => _navigateTo('signup'),
        );
      case 'signup':
        return SignupScreen(
          onToLogin: () { _popScreen(); },
        );
      case 'home':
        return HomeScreen(
          role: userRole,
          bookingState: bookingState,
          onStartBooking: startBooking,
          onCancelForm: () => setState(() => bookingState = 'idle'),
          onConfirmBooking: confirmBooking,
          eventType: eventType,
          onEventTypeChanged: (val) => setState(() => eventType = val),
          nameCtrl: _eventNameController,
          dateCtrl: _eventDateController,
          locCtrl: _eventLocController,
          onGoToAdminUser: () => _navigateTo('adminUsers'),
          onGoToAdminAmb: () => _navigateTo('adminAmbulances'),
          onGoToMap: () => _navigateTo('map'),
          onGoToAdminKegiatan: () => _navigateTo('adminKegiatan'),
          uploadedDocNames: _uploadedDocNames,
          onDocumentsChanged: (docs) =>
              setState(() => _uploadedDocNames = docs),
        );
      case 'map':
        return MapScreen(
          bookingState: bookingState,
          eventName: _eventNameController.text,
          eventDate: _eventDateController.text,
          eventLoc: _eventLocController.text,
          onCancel: cancelBooking,
        );
      case 'history':
        return HistoryScreen(history: historyList);
      case 'menu':
        return MenuScreen(
          onLogout: handleLogout,
          userName:  _currentUser?.name     ?? 'Pengguna',
          userEmail: _currentUser?.email    ?? '',
          userPhoto: _currentUser?.photoUrl ?? '',
          userId:    _currentUser?.uid      ?? '',
        );
      case 'adminUsers':
        return AdminUserScreen(onBack: _popScreen);
      case 'adminAmbulances':
        return AdminAmbulanceScreen(onBack: _popScreen);
      case 'adminKegiatan':
        return AdminKegiatanScreen(onBack: _popScreen);
      case 'notifSettings':
        return const NotificationScreen();
      default:
        return const Center(child: Text('Screen not found'));
    }
  }
}