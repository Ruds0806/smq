import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:smartqueue_rs/shared/api_client.dart';
import 'package:smartqueue_rs/shared/responsive.dart';
import 'package:smartqueue_rs/shared/session_store.dart';
import 'package:smartqueue_rs/shared/theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _identifier = TextEditingController();
  final _password   = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  late AnimationController _anim;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideIn;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeIn  = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _slideIn = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic));
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_identifier.text.trim().isEmpty || _password.text.isEmpty) {
      _snack('Mohon isi semua kolom', kOrange);
      return;
    }
    setState(() => _loading = true);
    try {
      final res = await ApiClient().postJson('/auth/patient-login', {
        'identifier': _identifier.text.trim(),
        'password': _password.text,
      });
      if (!mounted) return;
      await context.read<SessionStore>().saveToken(res['access_token']);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/queue/dashboard');
    } catch (e) {
      _snack(e.toString().replaceAll('Exception: ', ''), kRed);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          Icon(
            color == kRed
                ? Icons.error_outline_rounded
                : Icons.info_outline_rounded,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(msg)),
        ]),
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final size   = MediaQuery.of(context).size;

    return Scaffold(
      body: Stack(
        children: [
          // ── Background ──────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [const Color(0xFF080C18), const Color(0xFF0D1530), const Color(0xFF080C18)]
                    : [const Color(0xFFEEF4FF), const Color(0xFFF0F4FF), const Color(0xFFE8F5FF)],
              ),
            ),
          ),

          // ── Decorative blobs ────────────────────────────────────────────
          Positioned(
            top: -size.width * 0.35,
            right: -size.width * 0.25,
            child: _blob(size.width * 0.85,
                kPrimary.withValues(alpha: isDark ? 0.12 : 0.07)),
          ),
          Positioned(
            bottom: -size.width * 0.25,
            left: -size.width * 0.15,
            child: _blob(size.width * 0.65,
                kAccent.withValues(alpha: isDark ? 0.08 : 0.05)),
          ),

          // ── Content ─────────────────────────────────────────────────────
          SafeArea(
            child: Center(
              child: FadeTransition(
                opacity: _fadeIn,
                child: SlideTransition(
                  position: _slideIn,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 32),
                    child: ResponsiveContainer(
                      maxWidth: 420,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Logo
                          _buildLogo(),
                          const SizedBox(height: 28),

                          // Title
                          Text(
                            'SmartQueue RS',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.8,
                              color: isDark ? kLabelDark : kLabel,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Sistem Antrian Digital Rumah Sakit',
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark
                                  ? kSecondaryLabelDark
                                  : kSecondaryLabel,
                            ),
                          ),
                          const SizedBox(height: 40),

                          // Form card
                          _buildFormCard(isDark),
                          const SizedBox(height: 20),

                          // Login button
                          _buildLoginButton(),
                          const SizedBox(height: 28),

                          // Info hint
                          _buildHint(isDark),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _blob(double size, Color color) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, Colors.transparent]),
        ),
      );

  Widget _buildLogo() => Container(
        width: 76,
        height: 76,
        decoration: BoxDecoration(
          gradient: kPrimaryGradient,
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: kPrimary.withValues(alpha: 0.4),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: const Icon(Icons.local_hospital_rounded,
            color: Colors.white, size: 38),
      );

  Widget _buildFormCard(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? kSurfaceDark : kSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
            color: isDark ? kSeparatorDark : kSeparator),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: kPrimary.withValues(alpha: 0.07),
                  blurRadius: 36,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Column(
        children: [
          _buildField(
            controller: _identifier,
            hint: 'NIK atau No. Rekam Medis',
            icon: Icons.badge_outlined,
            isDark: isDark,
            isFirst: true,
          ),
          Divider(
              height: 0.5,
              thickness: 0.5,
              indent: 52,
              color: isDark ? kSeparatorDark : kSeparator),
          _buildField(
            controller: _password,
            hint: 'Password',
            icon: Icons.lock_outline_rounded,
            isDark: isDark,
            obscure: _obscure,
            isLast: true,
            suffix: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 20,
                color: isDark ? kSecondaryLabelDark : kSecondaryLabel,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoginButton() => SizedBox(
        width: double.infinity,
        height: 54,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: kPrimaryGradient,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: kPrimary.withValues(alpha: 0.38),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: FilledButton(
            onPressed: _loading ? null : _login,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15)),
            ),
            child: _loading
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.login_rounded, size: 20, color: Colors.white),
                      SizedBox(width: 8),
                      Text(
                        'Masuk',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                    ],
                  ),
          ),
        ),
      );

  Widget _buildHint(bool isDark) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: kPrimary.withValues(alpha: isDark ? 0.1 : 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: kPrimary.withValues(alpha: 0.18)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline_rounded,
                size: 16,
                color: kPrimary.withValues(alpha: 0.75)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Gunakan NIK atau No. Rekam Medis yang terdaftar di rumah sakit.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark
                      ? kSecondaryLabelDark
                      : kSecondaryLabel,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required bool isDark,
    bool obscure = false,
    bool isFirst = false,
    bool isLast  = false,
    Widget? suffix,
  }) {
    final radius = BorderRadius.only(
      topLeft:     Radius.circular(isFirst ? 19 : 0),
      topRight:    Radius.circular(isFirst ? 19 : 0),
      bottomLeft:  Radius.circular(isLast  ? 19 : 0),
      bottomRight: Radius.circular(isLast  ? 19 : 0),
    );
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(
          fontSize: 15,
          color: isDark ? kLabelDark : kLabel),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon,
            size: 20,
            color: isDark ? kSecondaryLabelDark : kSecondaryLabel),
        suffixIcon: suffix,
        filled: true,
        fillColor: Colors.transparent,
        border: OutlineInputBorder(
            borderRadius: radius, borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: radius, borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: radius, borderSide: BorderSide.none),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      ),
      onSubmitted: (_) => _login(),
    );
  }
}
