import 'package:fairest_one/app/app.dart';
import 'package:fairest_one/app/router.dart';
import 'package:fairest_one/features/registration/data/client_store.dart';
import 'package:fairest_one/features/registration/domain/client_record.dart';
import 'package:fairest_one/features/registration/presentation/registration_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() {
    dotenv.testLoad(
      fileInput: 'ADMIN_PASSWORD_HASH=8925260c8cb280b26321501c75eec6ffadccc51f05f1c0c54fd1a4f2a4e46861',
    );
  });

  setUp(() => appRouter.go('/'));

  testWidgets('shows the Fairest One dashboard', (tester) async {
    await tester.pumpWidget(const FairestOneApp());

    expect(find.text('Tableau de bord'), findsOneWidget);
    expect(find.text('Nouvelle session'), findsOneWidget);
    expect(find.textContaining('Miroir prêt'), findsOneWidget);
  });

  testWidgets('dashboard fits a mobile viewport', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const FairestOneApp());
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Tableau de bord'), findsOneWidget);
    expect(find.text('Administration'), findsOneWidget);
  });

  testWidgets('opens the photo recovery flow', (tester) async {
    await tester.pumpWidget(const FairestOneApp());

    await tester.tap(find.text('Récupérer mes photos'));
    await tester.pumpAndSettle();

    expect(find.text('Récupérer\nmes photos'), findsOneWidget);
    expect(find.text('SIMULER LA CARTE'), findsOneWidget);
  });

  testWidgets('validates email on registration screen', (tester) async {
    await tester.pumpWidget(const FairestOneApp());

    await tester.tap(find.text('Nouvelle session'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('CRÉER LA SESSION'));
    await tester.tap(find.text('CRÉER LA SESSION'));
    await tester.pump();

    expect(find.text('L’adresse email est obligatoire'), findsOneWidget);
  });

  testWidgets('stores a client with a simulated NFC card', (tester) async {
    final clientStore = _FakeClientStore();
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(home: RegistrationScreen(clientStore: clientStore)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('client-email-field')),
      'CLIENT@EXEMPLE.FR',
    );
    await tester.tap(find.byTooltip('Lire la carte NFC'));
    await tester.ensureVisible(find.text('CRÉER LA SESSION'));
    await tester.tap(find.text('CRÉER LA SESSION'));
    await tester.pumpAndSettle();

    expect(clientStore.clients.single.email, 'client@exemple.fr');
    expect(clientStore.clients.single.cardUid, startsWith('DEMO-'));
    expect(
      find.text('Client et carte NFC enregistrés sur cet appareil.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('unlocks the administration area with configured password', (
    tester,
  ) async {
    await tester.pumpWidget(const FairestOneApp());

    await tester.ensureVisible(find.text('Administration'));
    await tester.tap(find.text('Administration'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'iou');
    await tester.tap(find.text('DÉVERROUILLER'));
    await tester.pump();

    expect(find.text('Clients'), findsOneWidget);
    expect(find.text('Photos'), findsOneWidget);
    expect(find.text('Journal'), findsOneWidget);
  });
}

class _FakeClientStore implements ClientStore {
  final List<ClientRecord> clients = [];

  @override
  Future<ClientSaveResult> createClient({
    required String email,
    required String cardUid,
  }) async {
    clients.add(
      ClientRecord(
        id: 'test-client',
        email: email.trim().toLowerCase(),
        cardUid: cardUid.trim().toUpperCase(),
        photoCount: 0,
        createdAt: DateTime.utc(2026),
      ),
    );
    return ClientSaveResult.created;
  }

  @override
  Future<ClientRecord?> findByCardUid(String cardUid) async {
    for (final client in clients) {
      if (client.cardUid == cardUid.trim().toUpperCase()) return client;
    }
    return null;
  }

  @override
  Future<List<ClientRecord>> getClients() async => List.unmodifiable(clients);
}
