import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/app_theme.dart';
import '../data/client_store.dart';
import '../../mirror/data/nfc_flow_controller.dart';

class RegistrationScreen extends StatefulWidget {
  const RegistrationScreen({
    super.key,
    this.clientStore = const ConfiguredClientStore(),
    this.useMockIot = AppConfig.useMockIot,
    this.nfcController,
  });

  static const String routeName = 'registration';

  final ClientStore clientStore;
  final bool useMockIot;
  final NfcFlowController? nfcController;

  @override
  State<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends State<RegistrationScreen> {
  NfcFlowController get _nfc =>
      widget.nfcController ?? NfcFlowController.instance;
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _cardController = TextEditingController();

  bool _isSaving = false;
  bool _associated = false;

  @override
  void dispose() {
    if (!widget.useMockIot) _nfc.stop();
    _emailController.dispose();
    _cardController.dispose();
    super.dispose();
  }

  void _readCard() {
    if (_isSaving) return;
    if (!widget.useMockIot) {
      _submit();
      return;
    }

    final suffix = DateTime.now().millisecondsSinceEpoch
        .toRadixString(16)
        .toUpperCase();
    _cardController.text = 'DEMO-$suffix';
    setState(() {});
  }

  Future<void> _submit() async {
    if (_isSaving || !_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    if (!widget.useMockIot) {
      try {
        if (!_associated) {
          final result = await _nfc.read(
            'registration',
            email: _emailController.text,
          );
          if (!mounted) return;
          if (result['state'] == 'associated') {
            setState(() {
              _cardController.text = result['uid'] as String;
              _associated = true;
            });
          }
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_nfc.status.value)));
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(_nfc.status.value)));
        }
      } finally {
        if (mounted) setState(() => _isSaving = false);
      }
      return;
    }

    try {
      final result = await widget.clientStore.createClient(
        email: _emailController.text,
        cardUid: _cardController.text,
      );
      if (result == ClientSaveResult.created && widget.useMockIot) {
        try {
          await const DemoCardStore().save(_cardController.text);
        } catch (_) {
          // The remote client is already saved; demo-card caching is optional.
        }
      }
      if (!mounted) return;

      final message = switch (result) {
        ClientSaveResult.created =>
          'Client et carte NFC enregistrés dans Supabase.',
        ClientSaveResult.emailAlreadyExists =>
          'Cette adresse email est déjà enregistrée.',
        ClientSaveResult.cardAlreadyAssigned =>
          'Cette carte est déjà associée à un client.',
      };

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d’enregistrer ce client.')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

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
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: _OvalBadge(label: 'NOUVELLE SESSION'),
                  ),
                  const SizedBox(height: 30),
                  Text('Nouveau\nclient', style: textTheme.displayLarge),
                  const SizedBox(height: 14),
                  Text(
                    'Associez une adresse email à une carte NFC.',
                    style: textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 30),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          key: const Key('client-email-field'),
                          controller: _emailController,
                          readOnly: _isSaving,
                          onChanged: (_) {
                            if (_associated) {
                              setState(() {
                                _associated = false;
                                _cardController.clear();
                              });
                            }
                          },
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [AutofillHints.email],
                          autocorrect: false,
                          decoration: const InputDecoration(
                            labelText: 'Adresse email',
                            hintText: 'client@exemple.fr',
                            prefixIcon: Icon(Icons.mail_outline_rounded),
                          ),
                          validator: (value) {
                            final email = value?.trim() ?? '';
                            final isValid = RegExp(
                              r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                            ).hasMatch(email);

                            if (email.isEmpty) {
                              return 'L’adresse email est obligatoire';
                            }
                            if (!isValid) {
                              return 'Saisissez une adresse email valide';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          key: const Key('client-card-field'),
                          controller: _cardController,
                          readOnly: true,
                          decoration: InputDecoration(
                            labelText: 'Carte NFC',
                            hintText: 'Aucune carte associée',
                            prefixIcon: const Icon(Icons.contactless_outlined),
                            suffixIcon: IconButton(
                              tooltip: 'Lire la carte NFC',
                              onPressed: _isSaving ? null : _readCard,
                              icon: const Icon(Icons.sensors_rounded),
                            ),
                          ),
                          validator: (value) {
                            if (widget.useMockIot &&
                                (value == null || value.isEmpty)) {
                              return 'Présentez une carte NFC';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _CardStatus(
                    isAssociated: _cardController.text.isNotEmpty,
                    useMockIot: widget.useMockIot,
                  ),
                  if (!widget.useMockIot && _isSaving)
                    ValueListenableBuilder<String>(
                      valueListenable: _nfc.status,
                      builder: (context, value, _) =>
                          Semantics(liveRegion: true, child: Text(value)),
                    ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _isSaving || _associated ? null : _submit,
                    icon: _isSaving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: MinimalPalette.paper,
                            ),
                          )
                        : const Icon(Icons.arrow_forward_rounded),
                    label: Text(
                      _isSaving
                          ? 'ENREGISTREMENT...'
                          : _associated
                          ? 'SESSION CRÉÉE'
                          : 'CRÉER LA SESSION',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CardStatus extends StatelessWidget {
  const _CardStatus({required this.isAssociated, required this.useMockIot});

  final bool isAssociated;
  final bool useMockIot;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isAssociated
              ? Icons.check_circle_rounded
              : Icons.info_outline_rounded,
          size: 18,
          color: isAssociated ? MinimalPalette.sage : MinimalPalette.ink,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            isAssociated
                ? 'Carte prête pour l’essayage au miroir.'
                : useMockIot
                ? 'Touchez l’icône pour simuler une carte.'
                : 'Présentez la carte au lecteur de la borne.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _OvalBadge extends StatelessWidget {
  const _OvalBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: MinimalPalette.ink),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 9),
        child: Text(label, style: Theme.of(context).textTheme.titleMedium),
      ),
    );
  }
}
