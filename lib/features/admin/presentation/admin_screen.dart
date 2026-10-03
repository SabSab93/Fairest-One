import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../registration/data/client_store.dart';
import '../../registration/domain/client_record.dart';

enum _AdminSection { clients, photos, logs }

class AdminScreen extends StatefulWidget {
  const AdminScreen({
    super.key,
    this.clientStore = const ConfiguredClientStore(),
  });

  static const String routeName = 'admin';

  final ClientStore clientStore;

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final _pinController = TextEditingController();

  bool _isUnlocked = false;
  String? _pinError;
  String? _adminPassword;
  _AdminSection _section = _AdminSection.clients;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    try {
      await widget.clientStore.getClients(adminPassword: _pinController.text);
    } on AdminAccessDeniedException {
      if (mounted) {
        setState(() => _pinError = 'Mot de passe administrateur incorrect');
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() => _pinError = 'Impossible de joindre le serveur');
      }
      return;
    }

    if (!mounted) return;
    setState(() {
      _isUnlocked = true;
      _adminPassword = _pinController.text;
      _pinError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Retour au tableau de bord',
          onPressed: () => context.goNamed('home'),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
      ),
      body: SafeArea(
        child: _isUnlocked
            ? _AdminDashboard(
                clientStore: widget.clientStore,
                adminPassword: _adminPassword,
                section: _section,
                onSectionChanged: (section) =>
                    setState(() => _section = section),
              )
            : _AdminLock(
                controller: _pinController,
                errorText: _pinError,
                onSubmit: _unlock,
              ),
      ),
    );
  }
}

class _AdminLock extends StatelessWidget {
  const _AdminLock({
    required this.controller,
    required this.errorText,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String? errorText;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_outline_rounded, size: 42),
              const SizedBox(height: 22),
              Text(
                'Administration',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.displayLarge
                    ?.copyWith(fontSize: 56),
              ),
              const SizedBox(height: 10),
              Text(
                'Saisissez le code pour accéder aux données de la borne.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 28),
              TextField(
                controller: controller,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSubmit(),
                decoration: InputDecoration(
                  labelText: 'Mot de passe administrateur',
                  prefixIcon: const Icon(Icons.password_rounded),
                  errorText: errorText,
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: onSubmit,
                icon: const Icon(Icons.lock_open_rounded),
                label: const Text('DÉVERROUILLER'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminDashboard extends StatelessWidget {
  const _AdminDashboard({
    required this.clientStore,
    required this.adminPassword,
    required this.section,
    required this.onSectionChanged,
  });

  final ClientStore clientStore;
  final String? adminPassword;
  final _AdminSection section;
  final ValueChanged<_AdminSection> onSectionChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Administration',
                style: Theme.of(context).textTheme.displayLarge
                    ?.copyWith(fontSize: 58),
              ),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 680 ? 3 : 1;
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: columns == 3 ? 2.15 : 4.4,
                    children: [
                      _SectionButton(
                        icon: Icons.people_outline_rounded,
                        label: 'Clients',
                        isSelected: section == _AdminSection.clients,
                        onTap: () => onSectionChanged(_AdminSection.clients),
                      ),
                      _SectionButton(
                        icon: Icons.photo_library_outlined,
                        label: 'Photos',
                        isSelected: section == _AdminSection.photos,
                        onTap: () => onSectionChanged(_AdminSection.photos),
                      ),
                      _SectionButton(
                        icon: Icons.receipt_long_outlined,
                        label: 'Journal',
                        isSelected: section == _AdminSection.logs,
                        onTap: () => onSectionChanged(_AdminSection.logs),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 28),
              switch (section) {
                _AdminSection.clients => _ClientList(
                  clientStore: clientStore,
                  adminPassword: adminPassword,
                ),
                _AdminSection.photos => const _EmptyAdminView(
                  icon: Icons.photo_library_outlined,
                  title: 'Aucune photo synchronisée',
                  message: 'Les photos prises au miroir apparaîtront ici avec leur client.',
                ),
                _AdminSection.logs => const _LogView(),
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionButton extends StatelessWidget {
  const _SectionButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = isSelected ? MinimalPalette.paper : MinimalPalette.ink;

    return Material(
      color: isSelected ? MinimalPalette.ink : Colors.white,
      shape: RoundedRectangleBorder(
        side: BorderSide(
          color: isSelected ? MinimalPalette.ink : MinimalPalette.linen,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Icon(icon, color: foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: foreground, letterSpacing: 1),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClientList extends StatelessWidget {
  const _ClientList({required this.clientStore, required this.adminPassword});

  final ClientStore clientStore;
  final String? adminPassword;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ClientRecord>>(
      future: clientStore.getClients(adminPassword: adminPassword),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LinearProgressIndicator(minHeight: 2);
        }

        final clients = snapshot.data ?? const <ClientRecord>[];
        if (clients.isEmpty) {
          return const _EmptyAdminView(
            icon: Icons.people_outline_rounded,
            title: 'Aucun client enregistré',
            message: 'Les nouvelles sessions apparaîtront ici.',
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${clients.length} CLIENT${clients.length > 1 ? 'S' : ''}',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontSize: 12, letterSpacing: 1.4),
            ),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: MinimalPalette.linen),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  for (var index = 0; index < clients.length; index++) ...[
                    _ClientRow(client: clients[index]),
                    if (index != clients.length - 1)
                      const Divider(height: 1, indent: 54),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ClientRow extends StatelessWidget {
  const _ClientRow({required this.client});

  final ClientRecord client;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.person_outline_rounded),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  client.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 3),
                Text(
                  client.cardUid ?? 'Carte non associée',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: MinimalPalette.ink.withValues(alpha: 0.58),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${client.photoCount} photo${client.photoCount > 1 ? 's' : ''}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _LogView extends StatelessWidget {
  const _LogView();

  @override
  Widget build(BuildContext context) {
    final logs = [
      ('Application prête', 'Interface de la borne démarrée'),
      (
        AppConfig.useMockIot ? 'Mode simulation' : 'Mode matériel',
        AppConfig.useMockIot
            ? 'La Raspberry Pi n’est pas encore connectée'
            : 'Connexion à ${AppConfig.mirrorApiBaseUrl}',
      ),
    ];

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: MinimalPalette.linen),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (var index = 0; index < logs.length; index++) ...[
            ListTile(
              leading: const Icon(Icons.check_circle_outline_rounded),
              title: Text(logs[index].$1),
              subtitle: Text(logs[index].$2),
            ),
            if (index != logs.length - 1) const Divider(height: 1, indent: 54),
          ],
        ],
      ),
    );
  }
}

class _EmptyAdminView extends StatelessWidget {
  const _EmptyAdminView({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MinimalPalette.mist,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(icon, size: 34),
            const SizedBox(height: 14),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
