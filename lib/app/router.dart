import 'package:go_router/go_router.dart';

import '../features/admin/presentation/admin_screen.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/photo_recovery/presentation/photo_recovery_screen.dart';
import '../features/registration/presentation/registration_screen.dart';

final GoRouter appRouter = GoRouter(
  routes: <RouteBase>[
    GoRoute(
      path: '/',
      name: HomeScreen.routeName,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: '/registration',
      name: RegistrationScreen.routeName,
      builder: (context, state) => const RegistrationScreen(),
    ),
    GoRoute(
      path: '/photos',
      name: PhotoRecoveryScreen.routeName,
      builder: (context, state) => const PhotoRecoveryScreen(),
    ),
    GoRoute(
      path: '/admin',
      name: AdminScreen.routeName,
      builder: (context, state) => const AdminScreen(),
    ),
  ],
);
