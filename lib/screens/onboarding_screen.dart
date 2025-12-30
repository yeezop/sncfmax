import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  // Muted color palette
  static const Color _surfaceColor = Color(0xFFFFFFFF);
  static const Color _backgroundColor = Color(0xFFF8FAFC);
  static const Color _borderColor = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF1E293B);
  static const Color _textSecondary = Color(0xFF64748B);
  static const Color _textMuted = Color(0xFF94A3B8);
  static const Color _accentColor = Color(0xFF475569);

  final List<OnboardingPage> _pages = [
    OnboardingPage(
      icon: PhosphorIcons.train(PhosphorIconsStyle.duotone),
      title: 'Bienvenue sur TGV Max',
      subtitle: 'Trouvez facilement vos billets gratuits TGV Max en quelques secondes.',
      accentColor: const Color(0xFF64748B),
    ),
    OnboardingPage(
      icon: PhosphorIcons.calendarCheck(PhosphorIconsStyle.duotone),
      title: 'Calendrier intelligent',
      subtitle: 'Visualisez les disponibilites sur 90 jours. Les couleurs indiquent le nombre de places.',
      accentColor: const Color(0xFF059669),
    ),
    OnboardingPage(
      icon: PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.duotone),
      title: 'Recherche rapide',
      subtitle: 'Selectionnez vos gares et parcourez les trains disponibles instantanement.',
      accentColor: const Color(0xFF7C3AED),
    ),
    OnboardingPage(
      icon: PhosphorIcons.rocketLaunch(PhosphorIconsStyle.duotone),
      title: 'Pret a partir',
      subtitle: 'Commencez a explorer les disponibilites et reservez vos prochains voyages.',
      accentColor: const Color(0xFFDB2777),
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_complete', true);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
    } else {
      _completeOnboarding();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // Header with skip button
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Logo
                  Row(
                    children: [
                      Icon(
                        PhosphorIcons.train(PhosphorIconsStyle.fill),
                        size: 24,
                        color: _textPrimary,
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'TGV Max',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                    ],
                  ),
                  // Skip button
                  if (_currentPage < _pages.length - 1)
                    GestureDetector(
                      onTap: _completeOnboarding,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: _surfaceColor,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _borderColor),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Passer',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: _textSecondary,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
                              size: 14,
                              color: _textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Page content
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentPage = index;
                  });
                },
                itemCount: _pages.length,
                itemBuilder: (context, index) {
                  return _buildPage(_pages[index]);
                },
              ),
            ),

            // Bottom section
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Column(
                children: [
                  // Page indicators
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _pages.length,
                      (index) => _buildIndicator(index),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Next/Start button
                  GestureDetector(
                    onTap: _nextPage,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: _accentColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _currentPage == _pages.length - 1 ? 'Commencer' : 'Suivant',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            _currentPage == _pages.length - 1
                                ? PhosphorIcons.arrowRight(PhosphorIconsStyle.bold)
                                : PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
                            size: 20,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPage(OnboardingPage page) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Icon container
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: page.accentColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Center(
              child: Icon(
                page.icon,
                size: 72,
                color: page.accentColor,
              ),
            ),
          ),
          const SizedBox(height: 48),
          // Title
          Text(
            page.title,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: _textPrimary,
              letterSpacing: -0.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          // Subtitle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              page.subtitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: _textSecondary,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator(int index) {
    final isActive = index == _currentPage;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 32 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? _accentColor : _borderColor,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class OnboardingPage {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;

  OnboardingPage({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
  });
}
