import 'package:flutter/material.dart';
import 'register_page.dart';
import 'login_page.dart';


class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0A0E27), Color(0xFF12183D)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 56),

                // Ícono
                Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    color: const Color(0xFF4F8EF7).withValues(alpha: 0.12),
                    border: Border.all(
                      color: const Color(0xFF4F8EF7).withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(Icons.face_retouching_natural,
                      color: Color(0xFF4F8EF7), size: 32),
                ),

                const SizedBox(height: 36),

                const Text(
                  'FaceTion\nKR ',
                  style: TextStyle(
                    fontSize: 50,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    height: 1.05,
                    letterSpacing: -2,
                  ),
                ),

                const SizedBox(height: 14),

                Text(
                  'Esta aplicacion es perfecta, \npara un dia a dia con detección de emociones en tiempo real.',
                  style: TextStyle(
                    fontSize: 15,
                    color: Colors.white.withValues(alpha: 0.45),
                    height: 1.6,
                  ),
                ),

                const Spacer(),

                // Ilustración
                Center(
                  child: Stack(alignment: Alignment.center, children: [
                    _ring(280, 0.05),
                    _ring(220, 0.08),
                    _ring(160, 0.13),
                    Container(
                      width: 106,
                      height: 106,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [Color(0xFF4F8EF7), Color(0xFF7B5EA7)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF4F8EF7).withValues(alpha: 0.4),
                            blurRadius: 35,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.face_retouching_natural,
                          color: Colors.white, size: 52),
                    ),
                  ]),
                ),

                const Spacer(),

                // Botón principal - Ingresar
                _MainButton(
                  label: 'Ingresar a FaceTion',
                  icon: Icons.login_rounded,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF4F8EF7), Color(0xFF5E6EFF)],
                  ),
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const LoginPage())),
                ),

                const SizedBox(height: 14),

                // Botón secundario - Registrarse
                _OutlineButton(
                  label: 'Registrar',
                  icon: Icons.person_add_alt_1_rounded,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const RegisterPage())),
                ),


                const SizedBox(height: 44),

              ],

            ),
          ),
        ),
      ),
    );
  }

  Widget _ring(double size, double opacity) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: const Color(0xFF4F8EF7).withValues(alpha: opacity),
        width: 1.5,
      ),
    ),
  );
}

class _MainButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Gradient gradient;
  final VoidCallback onTap;

  const _MainButton(
      {required this.label,
        required this.icon,
        required this.gradient,
        required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 62,
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4F8EF7).withValues(alpha: 0.35),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3)),
          ],
        ),
      ),
    );
  }
}

class _OutlineButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _OutlineButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 62,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFF4F8EF7).withValues(alpha: 0.4),
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF4F8EF7), size: 22),
            const SizedBox(width: 10),
            Text(label,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4F8EF7),
                    letterSpacing: -0.3)),
          ],
        ),
      ),
    );
  }
}