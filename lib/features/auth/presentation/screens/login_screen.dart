import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/constants/app_colors.dart';
import '../providers/auth_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Entry widget
// ─────────────────────────────────────────────────────────────────────────────
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  late final AnimationController _floatCtrl;
  late final Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
    _floatAnim = Tween<double>(begin: -6, end: 6).animate(
      CurvedAnimation(parent: _floatCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _floatCtrl.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    await ref.read(authNotifierProvider.notifier).signIn(
          email: _emailCtrl.text.trim(),
          password: _passwordCtrl.text.trim(),
        );

    if (!mounted) return;

    final authState = ref.read(authNotifierProvider);
    authState.when(
      data: (profile) {
        if (profile != null) {
          switch (profile.role) {
            case 'super_admin':
              context.go('/super-admin');
              break;
            default:
              context.go('/dashboard');
          }
        } else {
          setState(() {
            _error = 'Login failed. Please try again.';
            _loading = false;
          });
        }
      },
      error: (e, _) => setState(() {
        _error = e.toString();
        _loading = false;
      }),
      loading: () => setState(() {
        _error = 'Login timed out. Please try again.';
        _loading = false;
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final isDesktop = w >= 900;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: isDesktop
          ? _DesktopLogin(state: this)
          : _MobileLogin(state: this),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Desktop layout: brand panel | form panel
// ─────────────────────────────────────────────────────────────────────────────
class _DesktopLogin extends StatelessWidget {
  final _LoginScreenState state;
  const _DesktopLogin({required this.state});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Row(
        children: [
          Expanded(
            flex: 5,
            child: _BrandPanel(floatAnim: state._floatAnim),
          ),
          Expanded(
            flex: 4,
            child: Container(
              color: AppColors.background,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment.bottomRight,
                          radius: 1.2,
                          colors: [
                            AppColors.primary.withValues(alpha: 0.05),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Positioned(
                    bottom: -80,
                    right: -80,
                    child: _Orb(size: 260, opacity: 0.10, color: AppColors.primary),
                  ),
                  const Positioned(
                    top: -60,
                    left: -60,
                    child: _Orb(size: 180, opacity: 0.06, color: AppColors.primary),
                  ),
                  Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 48, vertical: 48),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 44, vertical: 48),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            border: Border.all(
                                color: AppColors.border.withValues(alpha: 0.6)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 40,
                                offset: const Offset(0, 20),
                              ),
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.04),
                                blurRadius: 60,
                                spreadRadius: 4,
                              ),
                            ],
                          ),
                          child: _LoginForm(state: state, compact: false),
                        ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.03),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Mobile layout: curved gradient header with a card seamlessly overlapping it
// ─────────────────────────────────────────────────────────────────────────────
class _MobileLogin extends StatelessWidget {
  final _LoginScreenState state;
  const _MobileLogin({required this.state});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final topPad = MediaQuery.paddingOf(context).top;
    final headerHeight = size.height * 0.33 + topPad;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(44)),
                child: SizedBox(
                  height: headerHeight,
                  child: Padding(
                    padding: EdgeInsets.only(top: topPad),
                    child:
                        _BrandPanel(floatAnim: state._floatAnim, compact: true),
                  ),
                ),
              ),
              Transform.translate(
                offset: const Offset(0, -28),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 32),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.05),
                          blurRadius: 40,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: _LoginForm(state: state, compact: true),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Brand panel (shared between desktop left column & mobile header)
// ─────────────────────────────────────────────────────────────────────────────
class _BrandPanel extends StatelessWidget {
  final Animation<double> floatAnim;
  final bool compact;
  const _BrandPanel({required this.floatAnim, this.compact = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFE24A3B),
            Color(0xFFC0392B),
            Color(0xFF6E1B15),
          ],
          stops: [0.0, 0.5, 1.0],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(child: CustomPaint(painter: _GridPainter())),
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.topLeft,
                  radius: 1.3,
                  colors: [
                    Colors.white.withValues(alpha: 0.10),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          const Positioned(
            top: -60,
            right: -60,
            child: _Orb(size: 240, opacity: 0.12),
          ),
          Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: compact ? 24 : 48),
              child: compact
                  ? _CompactBrandContent(floatAnim: floatAnim)
                  : _FullBrandContent(floatAnim: floatAnim),
            ),
          ),
        ],
      ),
    );
  }
}

// Full brand content for desktop
class _FullBrandContent extends StatelessWidget {
  final Animation<double> floatAnim;
  const _FullBrandContent({required this.floatAnim});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedBuilder(
          animation: floatAnim,
          builder: (_, child) => Transform.translate(
            offset: Offset(0, floatAnim.value),
            child: child,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 122,
                height: 122,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.32),
                    width: 1.5,
                  ),
                ),
              ),
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: 20,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/katiyastationlogo.jpeg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
        ).animate().scale(
              delay: 150.ms,
              duration: 650.ms,
              curve: Curves.easeOutBack,
            ),

        const SizedBox(height: 30),

        Text(
          'KATIYA STATION',
          style: GoogleFonts.outfit(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 3,
          ),
        ).animate().fadeIn(delay: 350.ms).slideY(begin: 0.2),

        const SizedBox(height: 8),

        Text(
          'RESTAURANT & BAR MANAGEMENT',
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.65),
            letterSpacing: 3,
          ),
        ).animate().fadeIn(delay: 460.ms),

        const SizedBox(height: 44),

        Container(
          height: 1,
          width: double.infinity,
          color: Colors.white.withValues(alpha: 0.12),
        ).animate().fadeIn(delay: 540.ms),

        const SizedBox(height: 36),

        Row(
          children: [
            Expanded(
              child: const _FeatureCard(
                      icon: Icons.point_of_sale_rounded,
                      label: 'POS & Billing')
                  .animate()
                  .fadeIn(delay: 620.ms)
                  .slideY(begin: 0.12),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: const _FeatureCard(
                      icon: Icons.kitchen_rounded, label: 'Kitchen Display')
                  .animate()
                  .fadeIn(delay: 710.ms)
                  .slideY(begin: 0.12),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: const _FeatureCard(
                      icon: Icons.inventory_2_rounded,
                      label: 'Inventory & Bar')
                  .animate()
                  .fadeIn(delay: 800.ms)
                  .slideY(begin: 0.12),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: const _FeatureCard(
                      icon: Icons.query_stats_rounded,
                      label: 'Reports & Analytics')
                  .animate()
                  .fadeIn(delay: 890.ms)
                  .slideY(begin: 0.12),
            ),
          ],
        ),

        const SizedBox(height: 40),

        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_rounded,
                size: 13, color: Colors.white.withValues(alpha: 0.5)),
            const SizedBox(width: 8),
            Text(
              'Powered by Himnex Solutions Pvt. Ltd.',
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                color: Colors.white.withValues(alpha: 0.5),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ).animate().fadeIn(delay: 1050.ms),
      ],
    );
  }
}

// Compact brand for mobile header
class _CompactBrandContent extends StatelessWidget {
  final Animation<double> floatAnim;
  const _CompactBrandContent({required this.floatAnim});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedBuilder(
          animation: floatAnim,
          builder: (_, child) => Transform.translate(
            offset: Offset(0, floatAnim.value * 0.5),
            child: child,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 86,
                height: 86,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.32),
                    width: 1.5,
                  ),
                ),
              ),
              SizedBox(
                width: 70,
                height: 70,
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/katiyastationlogo.jpeg',
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ],
          ),
        ).animate().scale(
              delay: 100.ms,
              duration: 550.ms,
              curve: Curves.easeOutBack,
            ),
        const SizedBox(height: 16),
        Text(
          'KATIYA STATION',
          style: GoogleFonts.outfit(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            letterSpacing: 2.5,
          ),
        ).animate().fadeIn(delay: 200.ms),
        const SizedBox(height: 6),
        Text(
          'RESTAURANT & BAR MANAGEMENT',
          style: GoogleFonts.outfit(
            fontSize: 10.5,
            fontWeight: FontWeight.w400,
            color: Colors.white.withValues(alpha: 0.65),
            letterSpacing: 2,
          ),
        ).animate().fadeIn(delay: 300.ms),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Login form
// ─────────────────────────────────────────────────────────────────────────────
class _LoginForm extends StatefulWidget {
  final _LoginScreenState state;
  final bool compact;
  const _LoginForm({required this.state, required this.compact});

  @override
  State<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<_LoginForm> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final compact = widget.compact;

    return Form(
      key: state._formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'MANAGEMENT PORTAL',
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 2,
                color: AppColors.primary,
              ),
            ),
          ).animate().fadeIn(duration: 350.ms),

          const SizedBox(height: 10),

          Text(
            'Welcome back',
            style: GoogleFonts.outfit(
              fontSize: compact ? 25 : 29,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: AppColors.textPrimary,
            ),
          ).animate().fadeIn(delay: 60.ms).slideX(begin: 0.1),

          const SizedBox(height: 6),
          Text(
            'Sign in to manage your restaurant operations',
            style: GoogleFonts.outfit(
              fontSize: 13.5,
              color: AppColors.textSecondary,
            ),
          ).animate().fadeIn(delay: 120.ms),

          const SizedBox(height: 30),

          if (state._error != null)
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border:
                    Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline,
                      color: AppColors.error, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      state._error!,
                      style: const TextStyle(
                          color: AppColors.error, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ).animate().shake(),

          _ModernField(
            controller: state._emailCtrl,
            label: 'Email address',
            hint: 'you@example.com',
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            validator: (v) {
              if (v == null || v.isEmpty) return 'Email is required';
              if (!v.contains('@')) return 'Enter a valid email';
              return null;
            },
          ).animate().fadeIn(delay: 180.ms).slideY(begin: 0.08),

          const SizedBox(height: 18),

          _ModernField(
            controller: state._passwordCtrl,
            label: 'Password',
            hint: '••••••••',
            icon: Icons.lock_outline_rounded,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: AppColors.textHint,
                size: 20,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
            onFieldSubmitted: (_) => state._login(),
            validator: (v) {
              if (v == null || v.isEmpty) return 'Password is required';
              if (v.length < 6) return 'Minimum 6 characters';
              return null;
            },
          ).animate().fadeIn(delay: 250.ms).slideY(begin: 0.08),

          const SizedBox(height: 10),

          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                        'Please contact your manager or admin to reset your password.'),
                  ),
                );
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Forgot password?',
                style: GoogleFonts.outfit(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ),
          ).animate().fadeIn(delay: 300.ms),

          const SizedBox(height: 26),

          _SignInButton(
            loading: state._loading,
            onPressed: state._login,
          ).animate().fadeIn(delay: 340.ms).slideY(begin: 0.08),

          const SizedBox(height: 28),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.verified_user_outlined,
                  size: 14, color: AppColors.textHint),
              const SizedBox(width: 8),
              Text(
                'Secured with end-to-end encryption',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: AppColors.textHint,
                ),
              ),
            ],
          ).animate().fadeIn(delay: 420.ms),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Modern boxed text field with caption label
// ─────────────────────────────────────────────────────────────────────────────
class _ModernField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final bool obscureText;
  final Widget? suffixIcon;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final void Function(String)? onFieldSubmitted;

  const _ModernField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.obscureText = false,
    this.suffixIcon,
    this.keyboardType,
    this.textInputAction,
    this.validator,
    this.onFieldSubmitted,
  });

  @override
  State<_ModernField> createState() => _ModernFieldState();
}

class _ModernFieldState extends State<_ModernField> {
  final _focus = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() => _focused = _focus.hasFocus));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label.toUpperCase(),
          style: GoogleFonts.outfit(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: _focused ? AppColors.primary : AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: _focused ? Colors.white : const Color(0xFFF7F7F7),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _focused ? AppColors.primary : AppColors.border,
              width: _focused ? 1.6 : 1,
            ),
            boxShadow: _focused
                ? [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : [],
          ),
          child: TextFormField(
            controller: widget.controller,
            focusNode: _focus,
            obscureText: widget.obscureText,
            keyboardType: widget.keyboardType,
            textInputAction: widget.textInputAction,
            onFieldSubmitted: widget.onFieldSubmitted,
            validator: widget.validator,
            style: GoogleFonts.outfit(
              color: AppColors.textPrimary,
              fontSize: 15,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.hint,
              hintStyle:
                  GoogleFonts.outfit(color: AppColors.textHint, fontSize: 14),
              prefixIcon: Icon(
                widget.icon,
                size: 20,
                color: _focused ? AppColors.primary : AppColors.textHint,
              ),
              suffixIcon: widget.suffixIcon,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              focusedErrorBorder: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
              errorStyle: const TextStyle(color: AppColors.error, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Sign In button with red gradient
// ─────────────────────────────────────────────────────────────────────────────
class _SignInButton extends StatelessWidget {
  final bool loading;
  final VoidCallback onPressed;
  const _SignInButton({required this.loading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: loading ? null : onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: loading
                  ? const LinearGradient(
                      colors: [Color(0xFFCCCCCC), Color(0xFFBBBBBB)],
                    )
                  : const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFE53935),
                        Color(0xFFC0392B),
                        Color(0xFF8B1A1A),
                      ],
                    ),
              boxShadow: loading
                  ? null
                  : [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
            ),
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Sign In',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 18),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Feature card for the desktop brand panel's 2x2 feature grid
// ─────────────────────────────────────────────────────────────────────────────
class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureCard({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
            ),
            child: Icon(icon, color: Colors.white, size: 17),
          ),
          const SizedBox(height: 10),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Blurred decorative orb
// ─────────────────────────────────────────────────────────────────────────────
class _Orb extends StatelessWidget {
  final double size;
  final double opacity;
  final Color color;
  const _Orb({required this.size, required this.opacity, this.color = Colors.white});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: opacity),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Subtle dot grid background painter
// ─────────────────────────────────────────────────────────────────────────────
class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.035)
      ..strokeWidth = 0.8;

    const step = 44.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }

    final dotPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;

    for (double x = 0; x < size.width; x += step) {
      for (double y = 0; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), 1.4, dotPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
