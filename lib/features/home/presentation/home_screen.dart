import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../admin/presentation/admin_screen.dart';
import '../../mirror/data/mock_mirror_status_service.dart';
import '../../mirror/domain/mirror_status.dart';
import '../../photo_recovery/presentation/photo_recovery_screen.dart';
import '../../registration/presentation/registration_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const String routeName = 'home';

  @override
  Widget build(BuildContext context) {
    final status = const MockMirrorStatusService().currentStatus();

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _DoodlePainter()),
              ),
            ),
            LayoutBuilder(
              builder: (context, constraints) {
                final isCompact = constraints.maxWidth < 640;

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    isCompact ? 20 : 40,
                    isCompact ? 20 : 28,
                    isCompact ? 20 : 40,
                    28,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Header(status: status, isCompact: isCompact),
                          SizedBox(height: isCompact ? 42 : 62),
                          Text(
                            'Tableau de bord',
                            style: Theme.of(context).textTheme.displaySmall
                                ?.copyWith(
                                  fontFamily: 'Cormorant Garamond',
                                  fontSize: 48,
                                  fontWeight: FontWeight.w400,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Choisissez le parcours à démarrer.',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: MinimalPalette.ink.withValues(
                                    alpha: 0.64,
                                  ),
                                ),
                          ),
                          SizedBox(height: isCompact ? 26 : 34),
                          const _PrimaryActions(),
                          const SizedBox(height: 22),
                          _MirrorStatusPanel(status: status),
                          const SizedBox(height: 12),
                          const _AdminEntry(),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.status, required this.isCompact});

  final MirrorStatus status;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: MinimalPalette.ink,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(
            Icons.grid_view_rounded,
            color: MinimalPalette.paper,
            size: 21,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Fairest One',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontFamily: 'Cormorant Garamond',
                  fontSize: isCompact ? 25 : 29,
                  fontWeight: FontWeight.w400,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'BORNE D’ESSAYAGE',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.5),
              ),
            ],
          ),
        ),
        _ConnectionBadge(status: status, showLabel: !isCompact),
      ],
    );
  }
}

class _PrimaryActions extends StatelessWidget {
  const _PrimaryActions();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isSingleColumn = constraints.maxWidth < 660;

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: isSingleColumn ? 1 : 2,
          mainAxisSpacing: 14,
          crossAxisSpacing: 16,
          childAspectRatio: isSingleColumn ? 1.72 : 1.55,
          children: [
            _ActionCard(
              icon: Icons.add_rounded,
              title: 'Nouvelle session',
              subtitle: 'Créer un client et associer sa carte',
              backgroundColor: MinimalPalette.ink,
              foregroundColor: MinimalPalette.paper,
              onTap: () => context.goNamed(RegistrationScreen.routeName),
            ),
            _ActionCard(
              icon: Icons.photo_library_outlined,
              title: 'Récupérer mes photos',
              subtitle: 'Lire la carte et choisir les photos',
              backgroundColor: MinimalPalette.paleSage,
              onTap: () => context.goNamed(PhotoRecoveryScreen.routeName),
            ),
          ],
        );
      },
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.backgroundColor,
    required this.onTap,
    this.foregroundColor = MinimalPalette.ink,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: foregroundColor, size: 29),
              const Spacer(),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: foregroundColor,
                  fontFamily: 'Cormorant Garamond',
                  fontSize: 29,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: foregroundColor.withValues(alpha: 0.7)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MirrorStatusPanel extends StatelessWidget {
  const _MirrorStatusPanel({required this.status});

  final MirrorStatus status;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        border: Border.all(color: MinimalPalette.linen),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            const _StatusDot(),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${_statusLabel(status)} · disponible pour un essayage',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminEntry extends StatelessWidget {
  const _AdminEntry();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: MinimalPalette.ink.withValues(alpha: 0.14)),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.goNamed(AdminScreen.routeName),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
          child: Row(
            children: [
              const Icon(Icons.lock_outline_rounded, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Administration',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionBadge extends StatelessWidget {
  const _ConnectionBadge({required this.status, required this.showLabel});

  final MirrorStatus status;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Etat du miroir : ${_statusLabel(status)}',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: showLabel ? 14 : 10,
          vertical: 9,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.86),
          border: Border.all(color: MinimalPalette.linen),
          borderRadius: BorderRadius.circular(100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _StatusDot(),
            if (showLabel) ...[
              const SizedBox(width: 9),
              Text(
                'MIROIR PRÊT',
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 1.2),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: const BoxDecoration(
        color: MinimalPalette.sage,
        shape: BoxShape.circle,
      ),
    );
  }
}

String _statusLabel(MirrorStatus status) {
  return switch (status) {
    MirrorStatus.offline => 'Miroir hors ligne',
    MirrorStatus.ready => 'Miroir prêt',
    MirrorStatus.cardDetected => 'Carte détectée',
    MirrorStatus.countdown => 'Compte à rebours',
    MirrorStatus.takingPhoto => 'Photo en cours',
    MirrorStatus.photoUploaded => 'Photo envoyée',
    MirrorStatus.error => 'Erreur du miroir',
  };
}

class _DoodlePainter extends CustomPainter {
  const _DoodlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = MinimalPalette.ink.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final path = Path()
      ..moveTo(size.width * 0.2, 0)
      ..quadraticBezierTo(
        size.width * 0.4,
        size.height * 0.08,
        size.width * 0.58,
        size.height * 0.025,
      )
      ..quadraticBezierTo(
        size.width * 0.72,
        -8,
        size.width * 0.8,
        size.height * 0.1,
      );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
