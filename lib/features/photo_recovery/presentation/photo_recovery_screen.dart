import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../registration/data/client_store.dart';
import '../../registration/domain/client_record.dart';

class PhotoRecoveryScreen extends StatefulWidget {
  const PhotoRecoveryScreen({
    super.key,
    this.clientStore = const ConfiguredClientStore(),
  });

  static const String routeName = 'photo-recovery';

  final ClientStore clientStore;

  @override
  State<PhotoRecoveryScreen> createState() => _PhotoRecoveryScreenState();
}

class _PhotoRecoveryScreenState extends State<PhotoRecoveryScreen> {
  ClientRecord? _client;
  bool _isReading = false;

  Future<void> _readCard() async {
    if (_isReading) return;

    if (!AppConfig.useMockIot) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('En attente du lecteur RFID de la Raspberry Pi.'),
        ),
      );
      return;
    }

    setState(() => _isReading = true);
    final clients = await widget.clientStore.getClients();
    if (!mounted) return;

    ClientRecord? detectedClient;
    for (final client in clients) {
      if (client.cardUid != null) {
        detectedClient = client;
        break;
      }
    }

    setState(() {
      _client = detectedClient;
      _isReading = false;
    });

    if (detectedClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune carte client enregistrée.')),
      );
    }
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
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Récupérer\nmes photos',
                    style: Theme.of(context).textTheme.displayLarge,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Présentez la même carte NFC utilisée avant l’essayage.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  _ReaderPanel(
                    client: _client,
                    isReading: _isReading,
                    onRead: _readCard,
                  ),
                  if (_client != null) ...[
                    const SizedBox(height: 28),
                    _PhotoResult(client: _client!),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderPanel extends StatelessWidget {
  const _ReaderPanel({
    required this.client,
    required this.isReading,
    required this.onRead,
  });

  final ClientRecord? client;
  final bool isReading;
  final VoidCallback onRead;

  @override
  Widget build(BuildContext context) {
    final isDetected = client != null;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDetected ? MinimalPalette.paleSage : MinimalPalette.linen,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(
              isDetected
                  ? Icons.check_circle_outline_rounded
                  : Icons.contactless_outlined,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              isDetected ? 'Carte reconnue' : 'Lecteur NFC prêt',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontSize: 32),
            ),
            const SizedBox(height: 8),
            Text(
              isDetected
                  ? client!.email
                  : 'Approchez la carte du lecteur de la borne.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (!isDetected) ...[
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: isReading ? null : onRead,
                icon: isReading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sensors_rounded),
                label: Text(
                  AppConfig.useMockIot ? 'SIMULER LA CARTE' : 'LIRE LA CARTE',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PhotoResult extends StatelessWidget {
  const _PhotoResult({required this.client});

  final ClientRecord client;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'VOS PHOTOS',
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontSize: 12),
        ),
        const SizedBox(height: 12),
        DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: MinimalPalette.linen),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                const Icon(Icons.photo_library_outlined, size: 30),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    client.photoCount == 0
                        ? 'Aucune photo synchronisée pour cette session.'
                        : '${client.photoCount} photos prêtes à sélectionner.',
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
