import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'screens/backup_screen.dart';
import 'screens/configuracion_screen.dart';
import 'screens/historial_screen.dart';
import 'screens/home_screen.dart';
import 'screens/jugadores_screen.dart';
import 'screens/organizar_partido_screen.dart';
import 'screens/nuevo_partido_screen.dart';
import 'screens/historial_partidos_screen.dart';
import 'services/notification_service.dart';

final _navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es', null);
  await initializeDateFormatting('es_CL', null);
  await NotificationService.instance.initialize(navKey: _navigatorKey);
  runApp(PadelCobroApp(navigatorKey: _navigatorKey));
}

class PadelCobroApp extends StatelessWidget {
  final GlobalKey<NavigatorState> navigatorKey;

  const PadelCobroApp({super.key, required this.navigatorKey});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Pádel Cobro',
      debugShowCheckedModeBanner: false,
      locale: const Locale('es', 'CL'),
      supportedLocales: const [Locale('es', 'CL'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          foregroundColor: Colors.white,
          backgroundColor: Color(0xFF2E7D32),
          elevation: 2,
          iconTheme: IconThemeData(color: Colors.white),
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
      ),
      home: const MainShell(),
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
          final id = settings.arguments as int;
          return MaterialPageRoute(
            builder: (_) => HistorialScreen(jugadorId: id),
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

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  int _index = 0;

  late final List<Widget> _screens = [
    HomeScreen(onNavigateTab: (i) => setState(() => _index = i)),
    const JugadoresScreen(),
    const HistorialPartidosScreen(),
    const BackupScreen(),
    const ConfiguracionScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotificaciones();
  }

  Future<void> _initNotificaciones() async {
    final plugin = NotificationService.instance;
    await plugin.syncSchedule();
    await plugin.checkAndNotifyIfNeeded();

    final launch = await plugin.getLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      await plugin.handleLaunchPayload(launch?.notificationResponse?.payload);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      NotificationService.instance.syncSchedule();
      NotificationService.instance.checkAndNotifyIfNeeded();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: _screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Inicio',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Jugadores',
          ),
          NavigationDestination(
            icon: Icon(Icons.history),
            selectedIcon: Icon(Icons.history),
            label: 'Historial',
          ),
          NavigationDestination(
            icon: Icon(Icons.backup_outlined),
            selectedIcon: Icon(Icons.backup),
            label: 'Respaldo',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Config',
          ),
        ],
      ),
    );
  }
}
