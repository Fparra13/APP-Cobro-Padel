import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/acquisition_controller.dart';
import 'core/app_repositories.dart';
import 'core/app_settings_controller.dart';
import 'core/crashlytics_bootstrap.dart';
import 'core/matchpay_design_tokens.dart';
import 'core/offline_status_controller.dart';
import 'core/subscription_service.dart';
import 'core/auth_service.dart';
import 'core/firebase_config.dart';
import 'core/supabase_config.dart';
import 'offline/offline_refresh_coordinator.dart';
import 'screens/auth/login_screen.dart';
import 'screens/backup_screen.dart';
import 'screens/configuracion_screen.dart';
import 'screens/historial_screen.dart';
import 'screens/home_screen.dart';
import 'screens/jugadores_screen.dart';
import 'screens/mis_cobros_screen.dart';
import 'screens/organizer_cobros_screen.dart';
import 'screens/organizar_partido_screen.dart';
import 'screens/nuevo_partido_screen.dart';
import 'screens/historial_partidos_screen.dart';
import 'screens/onboarding/acquisition_screen.dart';
import 'screens/onboarding/sport_selection_screen.dart';
import 'screens/mi_historial_screen.dart';
import 'screens/player_home_screen.dart';
import 'services/fcm_service.dart' show FcmService, firebaseMessagingBackgroundHandler;
import 'services/notification_service.dart';
import 'services/supabase_realtime_service.dart';
import 'widgets/lazy_indexed_stack.dart';
import 'widgets/offline_readonly_banner.dart';
import 'widgets/kloovi_brand.dart';
import 'utils/nav_shell_layout.dart';
import 'widgets/mis_invitaciones_panel.dart';
import 'utils/formatters.dart' show MoneyFormatConfig;
import 'l10n/matchpay_strings.dart';
import 'utils/acquisition_navigation.dart';
import 'utils/matchpay_context.dart';
import 'utils/player_pay_bridge.dart';

final _navigatorKey = GlobalKey<NavigatorState>();
final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final offlineRefreshCoordinator = OfflineRefreshCoordinator();

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    if (FirebaseConfig.isConfigured) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      final firebaseOk = await FirebaseConfig.ensureInitialized();
      if (firebaseOk) {
        await CrashlyticsBootstrap.install();
      }
    }
    await initializeDateFormatting('es', null);
    await initializeDateFormatting('es_CL', null);
    await initializeDateFormatting('en', null);
    await initializeDateFormatting('pt_BR', null);
    await SupabaseConfig.initialize();
    final settings = AppSettingsController();
    await settings.load();
    final acquisition = AcquisitionController.instance;
    await acquisition.initialize();
    AuthService.instance.initializeAuthListener(
      onSignedIn: () {
        FcmService.instance.initialize();
        unawaited(settings.syncLocaleToProfile());
        offlineRefreshCoordinator.init();
        _navigatorKey.currentState?.popUntil((route) => route.isFirst);
      },
    );
    await NotificationService.instance.initialize(
      navKey: _navigatorKey,
      messengerKey: _scaffoldMessengerKey,
    );
    await NotificationService.instance.syncSchedule();
    _syncMoneyFormat(settings);
    await SubscriptionService.instance.load();
    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: settings),
          ChangeNotifierProvider.value(value: acquisition),
          ChangeNotifierProvider.value(value: SubscriptionService.instance),
          ChangeNotifierProvider(create: (_) => OfflineStatusController()),
        ],
        child: MatchPayApp(navigatorKey: _navigatorKey),
      ),
    );
  }, CrashlyticsBootstrap.recordZoneError);
}

void _syncMoneyFormat(AppSettingsController settings) {
  final currency = settings.currency;
  MoneyFormatConfig.locale = currency.locale;
  MoneyFormatConfig.symbol = currency.symbol;
  MoneyFormatConfig.decimalDigits = currency.decimalDigits;
  MoneyFormatConfig.dateLocale = settings.locale.languageCode;
}

class MatchPayApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const MatchPayApp({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<AppSettingsController>();
    _syncMoneyFormat(settings);

    return MaterialApp(
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      title: 'Kloovi',
      debugShowCheckedModeBanner: false,
      locale: settings.locale,
      supportedLocales: AppSettingsController.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: settings.theme,
      builder: (context, child) {
        final loggedIn = SupabaseConfig.isConfigured &&
            AuthService.instance.isLoggedIn &&
            AppRepositories.isReady;
        if (loggedIn) {
          return AppRepositoriesScope(
            repos: AppRepositories.I,
            child: child ?? const SizedBox.shrink(),
          );
        }
        return child ?? const SizedBox.shrink();
      },
      home: AcquisitionGate(
        child: SportOnboardingGate(
          child: AuthGate(navigatorKey: navigatorKey),
        ),
      ),
      routes: {
        '/jugadores': (_) => const JugadoresScreen(),
        '/nuevo-partido': (_) => const NuevoPartidoScreen(),
        '/organizar-partido': (_) => const OrganizarPartidoScreen(),
        '/partidos': (_) => const HistorialPartidosScreen(),
        '/configuracion': (_) => const ConfiguracionScreen(),
        '/backup': (_) => const BackupScreen(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/historial') {
          final key = settings.arguments as String;
          return MaterialPageRoute(
            builder: (_) => HistorialScreen(jugadorKey: key),
          );
        }
        if (settings.name == '/editar-partido') {
          final id = settings.arguments as int;
          return MaterialPageRoute(
            builder: (_) => NuevoPartidoScreen(partidoId: id),
          );
        }
        if (settings.name == '/editar-convocatoria') {
          final id = settings.arguments as int;
          return MaterialPageRoute(
            builder: (_) => OrganizarPartidoScreen(partidoId: id),
          );
        }
        if (settings.name == '/registrar-partido') {
          final id = settings.arguments as int;
          return MaterialPageRoute(
            builder: (_) => NuevoPartidoScreen(partidoId: id),
          );
        }
        return null;
      },
    );
  }
}

/// Redirige a LoginScreen o MainShell según la sesión de Supabase.
class AuthGate extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const AuthGate({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    if (!SupabaseConfig.isConfigured) {
      return const LoginScreen();
    }

    final initialSession = Supabase.instance.client.auth.currentSession;
    final initialAuth = initialSession != null
        ? AuthState(AuthChangeEvent.initialSession, initialSession)
        : null;

    return StreamBuilder<AuthState>(
      stream: AuthService.instance.authStateChanges,
      initialData: initialAuth,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: KlooviSplashLogo(height: 140, maxWidth: 320),
            ),
          );
        }

        final session = snapshot.data?.session;
        if (session != null) {
          try {
            AppRepositories.create();
          } on AppRepositoriesUnavailable {
            return const _CloudDataUnavailableScreen();
          }
          offlineRefreshCoordinator.init();
          return const RoleAwareShell();
        }
        return const LoginScreen();
      },
    );
  }
}

/// Pantalla cuando hay sesión pero no se puede abrir el repositorio cloud.
class _CloudDataUnavailableScreen extends StatelessWidget {
  const _CloudDataUnavailableScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.cloud_off_outlined,
                  size: 56,
                  color: Colors.grey.shade600,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.tr('profileLoadFailedTitle'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.tr('reposUnavailableSnackbar'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () async {
                    AppRepositories.clear();
                    await AuthService.instance.signOut();
                  },
                  icon: const Icon(Icons.logout),
                  label: Text(l10n.signOut),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Shell según rol: organizador (gestión) o jugador (convocatorias/cobros).
class RoleAwareShell extends StatefulWidget {
  const RoleAwareShell({super.key});

  @override
  State<RoleAwareShell> createState() => _RoleAwareShellState();
}

class _RoleAwareShellState extends State<RoleAwareShell> {
  bool _loading = true;
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final splashStarted = DateTime.now();
    if (mounted) {
      setState(() {
        _loading = true;
        _loadError = false;
      });
    }

    var profileOk = false;
    try {
      profileOk = await AuthService.instance
          .refreshProfile()
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      profileOk = false;
    } catch (_) {
      profileOk = false;
    }

    if (!mounted) return;

    await applyAcquisitionAfterLogin(context);

    if (!mounted) return;

    // Deja leer el slogan del splash antes de entrar al home.
    const minSplash = Duration(milliseconds: 2400);
    final elapsed = DateTime.now().difference(splashStarted);
    if (elapsed < minSplash) {
      await Future<void>.delayed(minSplash - elapsed);
    }

    if (!mounted) return;

    setState(() {
      _loadError = !profileOk && AuthService.instance.profileRole == null;
      _loading = false;
    });

    if (!_loadError) {
      unawaited(FcmService.instance.initialize());
      runPendingAcquisitionNavigation(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: KlooviSplashLogo(height: 140, maxWidth: 320),
        ),
      );
    }
    if (_loadError) {
      final l10n = context.l10n;
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.cloud_off_outlined,
                    size: 56,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.tr('profileLoadFailedTitle'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.tr('profileLoadFailedBody'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade700),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: _loadRole,
                    icon: const Icon(Icons.refresh),
                    label: Text(l10n.retry),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () async {
                      await AuthService.instance.signOut();
                    },
                    child: Text(l10n.signOut),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    // Organizador puede alternar vista; el rol viene solo de profiles.role.
    final settings = context.watch<AppSettingsController>();
    final showOrganizer =
        AuthService.instance.isOrganizer && settings.showOrganizerShell;
    return showOrganizer ? const OrganizerShell() : const PlayerShell();
  }
}

class OrganizerShell extends StatefulWidget {
  const OrganizerShell({super.key});

  @override
  State<OrganizerShell> createState() => _OrganizerShellState();
}

class _OrganizerShellState extends State<OrganizerShell>
    with WidgetsBindingObserver {
  int _index = 0;
  int _misCobrosCount = 0;

  late final List<Widget Function()> _screenBuilders = [
    () => HomeScreen(onNavigateTab: (i) => setState(() => _index = i)),
    () => const OrganizerCobrosScreen(),
    () => const JugadoresScreen(),
    () => const HistorialPartidosScreen(),
    () => const ConfiguracionScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.instance.registerOrganizerHomeNavigation(() {
      if (mounted) setState(() => _index = 0);
    });
    NotificationService.instance.registerOrganizerMisCobrosNavigation(() {
      if (mounted) setState(() => _index = 1);
    });
    AppRepositories.dataRevision.addListener(_onDataChanged);
    _initNotificaciones();
  }

  void _onDataChanged() {
    if (mounted) unawaited(_refreshMisCobrosCount());
  }

  Future<void> _initNotificaciones() async {
    SupabaseRealtimeService.instance.subscribeAppRefresh();
    final plugin = NotificationService.instance;
    await plugin.requestPermissions();
    await plugin.syncSchedule();
    await plugin.checkAndNotifyIfNeeded();
    await _refreshMisCobrosCount();

    final launch = await plugin.getLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      await plugin.handleLaunchPayload(launch?.notificationResponse?.payload);
    }
  }

  Future<void> _refreshMisCobrosCount() async {
    if (!AppRepositories.isReady) return;
    try {
      final resumen = await AppRepositories.I.getCobrosResumen();
      if (mounted) {
        setState(() => _misCobrosCount = resumen.jugadoresConDeuda);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    AppRepositories.dataRevision.removeListener(_onDataChanged);
    NotificationService.instance.onNavigateOrganizerHome = null;
    NotificationService.instance.onNavigateOrganizerMisCobros = null;
    SupabaseRealtimeService.instance.unsubscribeAppRefresh();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationService.instance.syncSchedule();
      NotificationService.instance.checkAndNotifyIfNeeded();
      AppRepositories.notifyDataChanged();
      unawaited(_refreshMisCobrosCount());
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.sportPalette;
    final settings = context.watchSettings();
    final cacheKey = settings.locale.languageCode;
    // Evita pantalla en blanco si el índice quedó fuera de rango
    // (p. ej. tras reducir pestañas con hot reload).
    final maxIndex = _screenBuilders.length - 1;
    if (_index > maxIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _index > maxIndex) {
          setState(() => _index = maxIndex.clamp(0, maxIndex));
        }
      });
    }
    final safeIndex = _index.clamp(0, maxIndex);

    Widget misCobrosIcon({required bool selected}) {
      final icon = Icon(
        selected ? Icons.receipt_long : Icons.receipt_long_outlined,
        color: selected ? palette.primary : null,
      );
      if (_misCobrosCount <= 0) return icon;
      return Badge(label: Text('$_misCobrosCount'), child: icon);
    }

    return Scaffold(
      body: Column(
        children: [
          const OfflineReadonlyBanner(),
          Expanded(
            child: NavShellScope(
              bottomInset: 72,
              child: LazyIndexedStack(
                index: safeIndex,
                cacheKey: cacheKey,
                itemBuilders: _screenBuilders,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 72,
          backgroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          indicatorColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? palette.primaryDark : MatchPayTokens.inkMuted,
              letterSpacing: 0,
              height: 1.15,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              size: 22,
              color: selected ? palette.primary : MatchPayTokens.inkMuted,
            );
          }),
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE8E6E1))),
          ),
          child: NavigationBar(
            selectedIndex: safeIndex,
            onDestinationSelected: (i) {
              if (i == safeIndex) return;
              setState(() => _index = i);
              if (i == 1) unawaited(_refreshMisCobrosCount());
            },
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home, color: palette.primary),
                label: l10n.navHome,
              ),
              NavigationDestination(
                icon: misCobrosIcon(selected: false),
                selectedIcon: misCobrosIcon(selected: true),
                label: l10n.navOrganizerCobros,
              ),
              NavigationDestination(
                icon: const Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people, color: palette.primary),
                label: l10n.navPlayers,
              ),
              NavigationDestination(
                icon: const Icon(Icons.history),
                selectedIcon: Icon(Icons.history, color: palette.primary),
                label: l10n.navHistory,
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings, color: palette.primary),
                label: l10n.navConfig,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PlayerShell extends StatefulWidget {
  const PlayerShell({super.key});

  @override
  State<PlayerShell> createState() => _PlayerShellState();
}

class _PlayerShellState extends State<PlayerShell> with WidgetsBindingObserver {
  int _index = 0;
  int _pendientesCount = 0;

  late final List<Widget Function()> _screenBuilders = [
    () => PlayerHomeScreen(
          onOpenMisCobros: () => setState(() => _index = 2),
          onOpenPartidos: () => setState(() => _index = 1),
          onPayTotalFromHome: _payTotalFromHome,
          onPayOtherFromHome: _payOtherFromHome,
        ),
    () => MiHistorialScreen(
          onOpenMisCobros: () => setState(() => _index = 2),
        ),
    () => const MisCobrosScreen(),
    () => const ConfiguracionScreen(),
  ];

  void _payTotalFromHome() {
    setState(() => _index = 2);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final started = await PlayerPayBridge.instance.requestPayTotal();
      if (!started && mounted) {
        NotificationService.instance.showInAppSnack(
          context.l10n.tr('cobrosNoOpenCharges'),
          context: context,
        );
      }
    });
  }

  void _payOtherFromHome() {
    setState(() => _index = 2);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final started = await PlayerPayBridge.instance.requestPayOther();
      if (!started && mounted) {
        NotificationService.instance.showInAppSnack(
          context.l10n.tr('cobrosNoOpenCharges'),
          context: context,
        );
      }
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    NotificationService.instance.registerPlayerMisCobrosNavigation(() {
      if (mounted) setState(() => _index = 2);
    });
    _initPlayer();
  }

  @override
  void dispose() {
    NotificationService.instance.onNavigatePlayerMisCobros = null;
    WidgetsBinding.instance.removeObserver(this);
    SupabaseRealtimeService.instance.unsubscribeAppRefresh();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      AppRepositories.notifyDataChanged();
      _refreshPendientes();
    }
  }

  Future<void> _initPlayer() async {
    SupabaseRealtimeService.instance.subscribeAppRefresh();
    final plugin = NotificationService.instance;
    await plugin.requestPermissions();
    await _refreshPendientes();

    final launch = await plugin.getLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      await plugin.handleLaunchPayload(launch?.notificationResponse?.payload);
    }
  }

  Future<void> _refreshPendientes() async {
    if (!AppRepositories.isReady) return;
    final pendientes =
        await MisInvitacionesPanel.cargarPendientes(AppRepositories.I);
    if (mounted) setState(() => _pendientesCount = pendientes.length);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final settings = context.watchSettings();
    final cacheKey = settings.locale.languageCode;
    final palette = context.sportPalette;
    final maxIndex = _screenBuilders.length - 1;
    if (_index > maxIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _index > maxIndex) {
          setState(() => _index = maxIndex.clamp(0, maxIndex));
        }
      });
    }
    final safeIndex = _index.clamp(0, maxIndex);

    Widget homeIcon({required bool selected}) {
      final icon = Icon(
        selected ? Icons.home_rounded : Icons.home_outlined,
        color: selected ? palette.primary : null,
      );
      if (_pendientesCount <= 0) return icon;
      return Badge(
        label: Text('$_pendientesCount', style: const TextStyle(fontSize: 10)),
        child: icon,
      );
    }

    return Scaffold(
      backgroundColor: MatchPayTokens.surfaceBase,
      body: Column(
        children: [
          const OfflineReadonlyBanner(),
          Expanded(
            child: NavShellScope(
              bottomInset: 72,
              child: LazyIndexedStack(
                index: safeIndex,
                cacheKey: cacheKey,
                itemBuilders: _screenBuilders,
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          height: 72,
          backgroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          indicatorColor: Colors.transparent,
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? palette.primaryDark : MatchPayTokens.inkMuted,
              letterSpacing: 0,
              height: 1.15,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              size: 22,
              color: selected ? palette.primary : MatchPayTokens.inkMuted,
            );
          }),
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE8E6E1))),
          ),
          child: NavigationBar(
            selectedIndex: safeIndex,
            onDestinationSelected: (i) async {
              if (i == safeIndex) return;
              setState(() => _index = i);
              if (i == 0) await _refreshPendientes();
            },
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              NavigationDestination(
                icon: homeIcon(selected: false),
                selectedIcon: homeIcon(selected: true),
                label: l10n.navHome,
              ),
              NavigationDestination(
                icon: const Icon(Icons.event_outlined),
                selectedIcon: Icon(Icons.event_rounded, color: palette.primary),
                label: l10n.navMyMatches,
              ),
              NavigationDestination(
                icon: const Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded, color: palette.primary),
                label: l10n.navMyCobros,
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded, color: palette.primary),
                label: l10n.navConfig,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// @deprecated Usar [OrganizerShell] vía [RoleAwareShell].
class MainShell extends OrganizerShell {
  const MainShell({super.key});
}
