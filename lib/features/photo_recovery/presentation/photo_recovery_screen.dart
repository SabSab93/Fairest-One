import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../nfc/data/phone_nfc_flow_controller.dart';
import '../../nfc/data/phone_nfc_reader.dart';
import '../../registration/data/client_store.dart';
import '../../mirror/data/nfc_flow_controller.dart';
import '../../registration/domain/client_record.dart';

class PhotoRecoveryScreen extends StatefulWidget {
  const PhotoRecoveryScreen({
    super.key,
    this.clientStore = const ConfiguredClientStore(),
    this.nfcController,
    this.useMockIot = AppConfig.useMockIot,
    this.usePhoneNfc = AppConfig.usePhoneNfc,
    this.phoneNfcController,
  });

  static const String routeName = 'photo-recovery';

  final ClientStore clientStore;
  final NfcFlowController? nfcController;
  final bool useMockIot;
  final bool usePhoneNfc;
  final PhoneNfcFlowController? phoneNfcController;

  @override
  State<PhotoRecoveryScreen> createState() => _PhotoRecoveryScreenState();
}

class _PhotoRecoveryScreenState extends State<PhotoRecoveryScreen> {
  PhoneNfcFlowController get _phoneNfc =>
      widget.phoneNfcController ?? PhoneNfcFlowController.instance;
  ValueNotifier<String> get _status =>
      widget.usePhoneNfc ? _phoneNfc.status : _nfc.status;
  Future<Map<String, dynamic>> _read(String purpose, {String? email}) =>
      widget.usePhoneNfc
      ? _phoneNfc.read(purpose, email: email)
      : _nfc.read(purpose, email: email);
  NfcFlowController get _nfc =>
      widget.nfcController ?? NfcFlowController.instance;
  ClientRecord? _client;
  bool _isReading = false;

  Future<void> _readCard() async {
    if (_isReading) return;

    setState(() => _isReading = true);
    try {
      if (!widget.useMockIot) {
        setState(() => _client = null);
        final result = await _read('recovery');
        if (!mounted) return;
        if (result['state'] == 'recovered') {
          final row = result['client'] as Map<String, dynamic>;
          setState(
            () => _client = ClientRecord(
              id: row['id'] as String,
              email: row['email'] as String,
              cardUid: row['card_uid'] as String?,
              photoCount: (row['photo_count'] as num).toInt(),
              createdAt: DateTime.parse(row['created_at'] as String),
              messages: (row['messages'] as List).cast<String>(),
            ),
          );
        } else {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(_status.value)));
        }
        return;
      }
      final cardUid = await const DemoCardStore().read();
      final detectedClient = cardUid == null
          ? null
          : await widget.clientStore.findByCardUid(cardUid);
      if (!mounted) return;

      setState(() => _client = detectedClient);
      if (detectedClient == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aucune carte client enregistrée.')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.useMockIot
                ? 'Impossible de rechercher cette carte.'
                : _status.value,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isReading = false);
    }
  }

  @override
  void dispose() {
    if (!widget.useMockIot) {
      if (widget.usePhoneNfc) {
        _phoneNfc.stop();
      } else {
        _nfc.stop();
      }
    }
    super.dispose();
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
                    useMockIot: widget.useMockIot,
                    usePhoneNfc: widget.usePhoneNfc,
                  ),
                  if (_isReading && !widget.useMockIot)
                    ValueListenableBuilder<String>(
                      valueListenable: _status,
                      builder: (context, value, _) =>
                          Semantics(liveRegion: true, child: Text(value)),
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
    required this.useMockIot,
    required this.usePhoneNfc,
  });

  final ClientRecord? client;
  final bool isReading;
  final VoidCallback onRead;
  final bool useMockIot;
  final bool usePhoneNfc;

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
                  : useMockIot
                  ? 'Touchez le bouton pour simuler une carte.'
                  : usePhoneNfc
                  ? 'Touchez « LIRE LA CARTE ». $phoneNfcInstruction'
                  : 'Approchez la carte du lecteur de la borne.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            ...[
              const SizedBox(height: 22),
              OutlinedButton.icon(
                onPressed: isReading ? null : onRead,
                icon: isReading
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sensors_rounded),
                label: Text(useMockIot ? 'SIMULER LA CARTE' : 'LIRE LA CARTE'),
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
                    client.messages.isNotEmpty
                        ? '${client.messages.length} captures simulées enregistrées.'
                        : client.photoCount == 0
                        ? 'Aucune photo synchronisée pour cette session.'
                        : '${client.photoCount} photos prêtes à sélectionner.',
                  ),
                ),
              ],
            ),
          ),
        ),
        for (final message in client.messages)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(message),
          ),
      ],
    );
  }
}
