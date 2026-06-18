// lib/screens/auth_screens.dart

import 'package:flutter/material.dart';
import '../widgets/painters.dart';
import '../service/auth_service.dart';
import '../service/notification_service.dart';
import '../models/user_models.dart';

// ─── Warna soft/muted (tidak mencolok) ────────────────────────────────
const _kPrimary       = Color(0xFFC0392B); // muted crimson
const _kPrimaryLight  = Color(0xFFEDD9D7); // blush lembut
const _kBg            = Color(0xFFF7F5F3); // warm off-white
const _kSurface       = Color(0xFFFFFFFF);
const _kBorder        = Color(0xFFE8E4E1);
const _kTextPrimary   = Color(0xFF2C2520);
const _kTextSecondary = Color(0xFF7A706A);
const _kTextMuted     = Color(0xFFAA9E98);
const _kSuccess       = Color(0xFF2E7D6B);
const _kWarning       = Color(0xFFB7600A);


// ═══════════════════════════════════════════════════════════════════
// WELCOME SCREEN
// ═══════════════════════════════════════════════════════════════════
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // Gradient lembut di belakang
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFEDE5E3), _kBg],
                  stops: [0.0, 0.5],
                ),
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(child: BottomCityPainter()),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLogo(200),
                const SizedBox(height: 28),
                const Text(
                  "AMBUEVENT",
                  style: TextStyle(
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 5,
                    color: _kPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  "DINKES KABUPATEN MADIUN",
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _kTextMuted,
                    letterSpacing: 2.5,
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


// ═══════════════════════════════════════════════════════════════════
// LOGIN SCREEN
// ═══════════════════════════════════════════════════════════════════
class LoginScreen extends StatefulWidget {
  final Function(String role, {UserModel? user}) onLogin;
  final VoidCallback onToSignup;

  const LoginScreen({
    super.key,
    required this.onLogin,
    required this.onToSignup,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _emailController    = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscure   = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _kBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFEDE5E3), _kBg],
                  stops: [0.0, 0.4],
                ),
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(child: BottomCityPainter()),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
              child: Column(
                children: [
                  const SizedBox(height: 36),
                  _buildLogo(110),
                  const SizedBox(height: 18),
                  const Text(
                    "AMBUEVENT",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                      color: _kPrimary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    "Masuk ke akun Anda",
                    style: TextStyle(
                      fontSize: 13,
                      color: _kTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 32),

                  _AuthField(
                    hint: "Email",
                    icon: Icons.mail_outline_rounded,
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _AuthField(
                    hint: "Password",
                    icon: Icons.lock_outline_rounded,
                    controller: _passwordController,
                    isObscure: _obscure,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: _kTextMuted,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (_isLoading)
                    const SizedBox(
                      height: 50,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: _kPrimary, strokeWidth: 2.5,
                        ),
                      ),
                    )
                  else
                    Column(children: [
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _handleEmailLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPrimary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            "Masuk",
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Divider "atau"
                      Row(children: [
                        const Expanded(child: Divider(color: _kBorder)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            "atau",
                            style: TextStyle(color: _kTextMuted, fontSize: 12),
                          ),
                        ),
                        const Expanded(child: Divider(color: _kBorder)),
                      ]),
                      const SizedBox(height: 16),

                      // Google button
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton(
                          onPressed: _handleGoogleSignIn,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _kTextPrimary,
                            side: const BorderSide(color: _kBorder, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 22, height: 22,
                                decoration: BoxDecoration(
                                  color: _kPrimaryLight,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: const Center(
                                  child: Text(
                                    "G",
                                    style: TextStyle(
                                      color: _kPrimary,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text(
                                "Lanjutkan dengan Google",
                                style: TextStyle(
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                  color: _kTextPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text(
                            "Belum punya akun? ",
                            style: TextStyle(
                                color: _kTextSecondary, fontSize: 13),
                          ),
                          GestureDetector(
                            onTap: widget.onToSignup,
                            child: const Text(
                              "Daftar sekarang",
                              style: TextStyle(
                                color: _kPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ]),
                  const SizedBox(height: 150),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleEmailLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      _showSnack("Email dan password wajib diisi.");
      return;
    }
    setState(() => _isLoading = true);
    final user = await _authService.signInWithEmail(
      _emailController.text.trim(),
      _passwordController.text,
    );
    setState(() => _isLoading = false);
    if (user != null) {
      await NotificationService().onUserLoggedIn(user.uid);
      widget.onLogin(user.role, user: user);
    } else {
      _showSnack("Email atau password salah.");
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isLoading = true);
    final result = await _authService.signInWithGoogle();
    setState(() => _isLoading = false);

    switch (result.status) {
      case GoogleAuthStatus.success:
        await NotificationService().onUserLoggedIn(result.user!.uid);
        widget.onLogin(result.user!.role, user: result.user);
        break;
      case GoogleAuthStatus.notRegistered:
        _showSnack(
          "Akun Google ini belum terdaftar. Silakan daftar terlebih dahulu.",
          isWarning: true,
        );
        break;
      case GoogleAuthStatus.cancelled:
        break;
      default:
        _showSnack(result.errorMessage ?? "Login Google gagal.");
    }
  }

  void _showSnack(String message, {bool isWarning = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 13)),
      backgroundColor: isWarning ? _kWarning : _kPrimary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }
}


// ═══════════════════════════════════════════════════════════════════
// SIGNUP SCREEN
// ═══════════════════════════════════════════════════════════════════
class SignupScreen extends StatefulWidget {
  final VoidCallback onToLogin;
  const SignupScreen({super.key, required this.onToLogin});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final AuthService _authService = AuthService();
  final TextEditingController _nameController     = TextEditingController();
  final TextEditingController _emailController    = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscure   = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: _kBg,
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFFEDE5E3), _kBg],
                  stops: [0.0, 0.4],
                ),
              ),
            ),
          ),
          const Align(
            alignment: Alignment.bottomCenter,
            child: IgnorePointer(child: BottomCityPainter()),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 36),
                  _buildLogo(110),
                  const SizedBox(height: 18),
                  const Text(
                    "AMBUEVENT",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4,
                      color: _kPrimary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    "Buat akun baru",
                    style: TextStyle(fontSize: 13, color: _kTextSecondary),
                  ),
                  const SizedBox(height: 32),

                  _AuthField(
                    hint: "Nama Lengkap",
                    icon: Icons.person_outline_rounded,
                    controller: _nameController,
                  ),
                  const SizedBox(height: 12),
                  _AuthField(
                    hint: "Email",
                    icon: Icons.mail_outline_rounded,
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  _AuthField(
                    hint: "Password (min. 6 karakter)",
                    icon: Icons.lock_outline_rounded,
                    controller: _passwordController,
                    isObscure: _obscure,
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18,
                        color: _kTextMuted,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (_isLoading)
                    const SizedBox(
                      height: 50,
                      child: Center(
                        child: CircularProgressIndicator(
                            color: _kPrimary, strokeWidth: 2.5),
                      ),
                    )
                  else
                    Column(children: [
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _handleRegister,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _kPrimary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text(
                            "Daftar",
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 15),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(children: [
                        const Expanded(child: Divider(color: _kBorder)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text("atau",
                              style:
                                  TextStyle(color: _kTextMuted, fontSize: 12)),
                        ),
                        const Expanded(child: Divider(color: _kBorder)),
                      ]),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: OutlinedButton(
                          onPressed: _handleGoogleRegister,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _kTextPrimary,
                            side: const BorderSide(
                                color: _kBorder, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 22, height: 22,
                                decoration: BoxDecoration(
                                  color: _kPrimaryLight,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: const Center(
                                  child: Text("G",
                                      style: TextStyle(
                                        color: _kPrimary,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                      )),
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Text("Daftar dengan Google",
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    color: _kTextPrimary,
                                  )),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text("Sudah punya akun? ",
                              style: TextStyle(
                                  color: _kTextSecondary, fontSize: 13)),
                          GestureDetector(
                            onTap: widget.onToLogin,
                            child: const Text("Masuk",
                                style: TextStyle(
                                  color: _kPrimary,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                )),
                          ),
                        ],
                      ),
                    ]),
                  const SizedBox(height: 130),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleRegister() async {
    if (_nameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      _showSnack("Semua kolom wajib diisi.");
      return;
    }
    setState(() => _isLoading = true);
    final user = await _authService.registerWithEmail(
      _emailController.text.trim(),
      _passwordController.text,
      _nameController.text,
    );
    setState(() => _isLoading = false);
    if (user != null) {
      _showSnack("Registrasi berhasil! Silakan masuk.", isSuccess: true);
      widget.onToLogin();
    } else {
      _showSnack("Registrasi gagal. Email mungkin sudah digunakan.");
    }
  }

  Future<void> _handleGoogleRegister() async {
    setState(() => _isLoading = true);
    final result = await _authService.registerWithGoogle();
    setState(() => _isLoading = false);

    switch (result.status) {
      case GoogleAuthStatus.success:
        if (!mounted) return;
        await NotificationService().onUserLoggedIn(result.user!.uid);
        _showSnack("Registrasi berhasil!", isSuccess: true);
        break;
      case GoogleAuthStatus.alreadyExists:
        _showSnack(
          "Email ini sudah terdaftar. Silakan masuk.",
          isWarning: true,
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) widget.onToLogin();
        });
        break;
      case GoogleAuthStatus.cancelled:
        break;
      default:
        _showSnack(result.errorMessage ?? "Pendaftaran Google gagal.");
    }
  }

  void _showSnack(String message,
      {bool isSuccess = false, bool isWarning = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(fontSize: 13)),
      backgroundColor:
          isSuccess ? _kSuccess : isWarning ? _kWarning : _kPrimary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
    ));
  }
}


// ═══════════════════════════════════════════════════════════════════
// SHARED WIDGETS
// ═══════════════════════════════════════════════════════════════════
Widget _buildLogo(double size) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: _kSurface,
      shape: BoxShape.circle,
      boxShadow: [
        BoxShadow(
          color: _kPrimary.withValues(alpha: 0.12),
          blurRadius: 24,
          spreadRadius: 4,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.05),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: ClipOval(
      child: Image.asset(
        'assets/images/logo_ambuevent.png',
        fit: BoxFit.cover,
      ),
    ),
  );
}

/// Input field yang dipakai di halaman auth
class _AuthField extends StatelessWidget {
  final String hint;
  final IconData icon;
  final TextEditingController? controller;
  final bool isObscure;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;

  const _AuthField({
    required this.hint,
    required this.icon,
    this.controller,
    this.isObscure = false,
    this.keyboardType,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        obscureText: isObscure,
        keyboardType: keyboardType,
        style: const TextStyle(
          color: _kTextPrimary,
          fontSize: 14,
        ),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: _kTextMuted, fontSize: 14),
          prefixIcon: Icon(icon, color: _kTextMuted, size: 18),
          suffixIcon: suffixIcon,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        ),
      ),
    );
  }
}