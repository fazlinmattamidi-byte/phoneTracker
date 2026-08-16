import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'anpr/consensus.dart';
import 'anpr/matching_engine.dart';
import 'anpr/native_anpr_bridge.dart';
import 'anpr/normaliser.dart';
import 'anpr/plate_types.dart';
import 'anpr/special_series.dart';
import 'core/app_state.dart';
import 'core/domain.dart';
import 'core/localization.dart';
import 'core/native_share.dart';

class TrackColors {
  static const bg = Color(0xFF090C15);
  static const bgDeep = Color(0xFF020617);
  static const panel = Color(0xE60F172A);
  static const panelSolid = Color(0xFF0F172A);
  static const panelSoft = Color(0x991E293B);
  static const field = Color(0xFF020617);
  static const border = Color(0xFF1E293B);
  static const cyanBorder = Color(0x80155E75);
  static const cyan = Color(0xFF22D3EE);
  static const cyanStrong = Color(0xFF06B6D4);
  static const text = Color(0xFFF8FAFC);
  static const muted = Color(0xFF94A3B8);
  static const muted2 = Color(0xFF64748B);
  static const blue = Color(0xFF60A5FA);
  static const purple = Color(0xFFC084FC);
  static const emerald = Color(0xFF34D399);
  static const amber = Color(0xFFFBBF24);
  static const red = Color(0xFFF87171);
}

class TrackPalette {
  const TrackPalette({
    required this.isDark,
    required this.bg,
    required this.bgDeep,
    required this.panel,
    required this.panelSolid,
    required this.panelSoft,
    required this.field,
    required this.border,
    required this.cyanBorder,
    required this.cyan,
    required this.cyanStrong,
    required this.text,
    required this.muted,
    required this.muted2,
    required this.blue,
    required this.purple,
    required this.emerald,
    required this.amber,
    required this.red,
    required this.shadow,
  });

  final bool isDark;
  final Color bg;
  final Color bgDeep;
  final Color panel;
  final Color panelSolid;
  final Color panelSoft;
  final Color field;
  final Color border;
  final Color cyanBorder;
  final Color cyan;
  final Color cyanStrong;
  final Color text;
  final Color muted;
  final Color muted2;
  final Color blue;
  final Color purple;
  final Color emerald;
  final Color amber;
  final Color red;
  final Color shadow;

  static const dark = TrackPalette(
    isDark: true,
    bg: TrackColors.bg,
    bgDeep: TrackColors.bgDeep,
    panel: TrackColors.panel,
    panelSolid: TrackColors.panelSolid,
    panelSoft: TrackColors.panelSoft,
    field: TrackColors.field,
    border: TrackColors.border,
    cyanBorder: TrackColors.cyanBorder,
    cyan: TrackColors.cyan,
    cyanStrong: TrackColors.cyanStrong,
    text: TrackColors.text,
    muted: TrackColors.muted,
    muted2: TrackColors.muted2,
    blue: TrackColors.blue,
    purple: TrackColors.purple,
    emerald: TrackColors.emerald,
    amber: TrackColors.amber,
    red: TrackColors.red,
    shadow: Color(0x66020617),
  );

  static const light = TrackPalette(
    isDark: false,
    bg: Color(0xFFF8FAFC),
    bgDeep: Color(0xFFEEF5FB),
    panel: Color(0xF2FFFFFF),
    panelSolid: Color(0xFFFFFFFF),
    panelSoft: Color(0xFFF1F5F9),
    field: Color(0xFFF8FAFC),
    border: Color(0xFFCBD5E1),
    cyanBorder: Color(0xFFBFDBFE),
    cyan: Color(0xFF0284C7),
    cyanStrong: Color(0xFF0891B2),
    text: Color(0xFF0F172A),
    muted: Color(0xFF475569),
    muted2: Color(0xFF64748B),
    blue: Color(0xFF2563EB),
    purple: Color(0xFF7C3AED),
    emerald: Color(0xFF047857),
    amber: Color(0xFFB45309),
    red: Color(0xFFDC2626),
    shadow: Color(0x171E293B),
  );

  factory TrackPalette.fromBrightness(Brightness brightness) {
    return brightness == Brightness.dark ? dark : light;
  }

  static TrackPalette of(BuildContext context) {
    return AppScope.of(context).themeChoice == AppThemeChoice.dark
        ? dark
        : light;
  }

  Color tint(Color tone, [int alpha = 38]) {
    return Color.alphaBlend(tone.withAlpha(alpha), field);
  }
}

class PlateQMobileApp extends StatefulWidget {
  const PlateQMobileApp({super.key});

  @override
  State<PlateQMobileApp> createState() => _PlateQMobileAppState();
}

class _PlateQMobileAppState extends State<PlateQMobileApp> {
  late final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    unawaited(_state.restoreSession());
  }

  @override
  void dispose() {
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: _state,
      child: AnimatedBuilder(
        animation: _state,
        builder: (context, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'TRACK',
            theme: _buildTheme(_state.themeChoice == AppThemeChoice.light
                ? Brightness.light
                : Brightness.dark),
            home: !_state.authReady
                ? const StartupScreen()
                : _state.isAuthenticated
                    ? const PlateQShell()
                    : const LoginScreen(),
          );
        },
      ),
    );
  }
}

ThemeData _buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final colors = TrackPalette.fromBrightness(brightness);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: colors.bg,
    fontFamily: 'Roboto',
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors.cyanStrong,
      brightness: brightness,
      surface: colors.panelSolid,
      primary: colors.cyanStrong,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.panel,
      foregroundColor: colors.text,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: colors.panel,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.field,
      selectedColor: colors.tint(colors.cyan, 46),
      disabledColor: colors.panelSoft,
      side: BorderSide(color: colors.border),
      labelStyle: TextStyle(
        color: colors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
      secondaryLabelStyle: TextStyle(
        color: colors.cyan,
        fontSize: 11,
        fontWeight: FontWeight.w900,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.cyanStrong,
        foregroundColor: isDark ? colors.bgDeep : Colors.white,
        minimumSize: const Size.fromHeight(44),
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 0,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.text,
        side: BorderSide(color: colors.border),
        minimumSize: const Size.fromHeight(44),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.cyan,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: colors.muted,
        backgroundColor: colors.panelSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: colors.border),
        ),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colors.cyan,
      textColor: colors.text,
      titleTextStyle: TextStyle(
        color: colors.text,
        fontSize: 14,
        fontWeight: FontWeight.w800,
      ),
      subtitleTextStyle: TextStyle(
        color: colors.muted,
        fontSize: 12,
        height: 1.35,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.panelSolid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.border),
      ),
      textStyle: TextStyle(
        color: colors.text,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.field,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.border),
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.field,
      labelStyle: TextStyle(
        color: colors.muted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      prefixIconColor: colors.muted2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colors.cyanStrong),
      ),
    ),
    textTheme: (isDark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
          bodyColor: colors.text,
          displayColor: colors.text,
        ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.panelSolid,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.border),
      ),
    ),
  );
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    super.key,
    required AppState notifier,
    required super.child,
  }) : super(notifier: notifier);

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope is missing');
    return scope!.notifier!;
  }
}

class StartupScreen extends StatelessWidget {
  const StartupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  Role _selectedRole = Role.superAdmin;
  late final TextEditingController _email =
      TextEditingController(text: 'superadmin@track.my');
  late final TextEditingController _password =
      TextEditingController(text: 'password');
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _selectRole(Role role) {
    final state = AppScope.of(context);
    final user = state.users.firstWhere((item) => item.role == role,
        orElse: () => state.users.first);
    setState(() {
      _selectedRole = role;
      _email.text = user.email;
    });
  }

  Future<void> _submit() async {
    final state = AppScope.of(context);
    setState(() => _busy = true);
    final success = await state.loginWithCredentials(
      email: _email.text,
      password: _password.text,
      fallbackRole: _selectedRole,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (!success && state.authError != null) {
      _showSnack(context, state.authError!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    final roles = <Role>[Role.user, Role.admin, Role.superAdmin];
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: colors.bgDeep,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.cyanBorder),
                        boxShadow: [
                          BoxShadow(
                              color: colors.cyan.withAlpha(34), blurRadius: 22),
                        ],
                      ),
                      child: Image.asset('public/logo.png', fit: BoxFit.cover),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'TRACK',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    state.t('appSubName'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 32),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '${state.t('demoRole')} (Select for Demo)',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: colors.cyan,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            for (final role in roles)
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 4),
                                  child: _LoginRoleTile(
                                    role: role,
                                    selected: _selectedRole == role,
                                    label: _roleLabel(state, role),
                                    onTap: () => _selectRole(role),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(state.t('loginTitle'),
                            style: TextStyle(
                              color: colors.text,
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                            )),
                        const SizedBox(height: 4),
                        Text(
                          state.t('loginSubtitle'),
                          style: TextStyle(color: colors.muted, fontSize: 12),
                        ),
                        const SizedBox(height: 18),
                        TextField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          decoration: const InputDecoration(
                            labelText: 'Email Address',
                            prefixIcon: Icon(Icons.mail_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                        if (state.authError != null) ...[
                          const SizedBox(height: 10),
                          Text(
                            state.authError!,
                            style: const TextStyle(
                                color: Color(0xFFF87171),
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: Icon(_busy
                              ? Icons.hourglass_empty
                              : Icons.arrow_forward),
                          label: Text(state.t('loginButton')),
                        ),
                      ],
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

class _LoginRoleTile extends StatelessWidget {
  const _LoginRoleTile({
    required this.role,
    required this.selected,
    required this.label,
    required this.onTap,
  });

  final Role role;
  final bool selected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    final icon = switch (role) {
      Role.user => Icons.person_outline,
      Role.admin => Icons.verified_user_outlined,
      Role.superAdmin => Icons.shield_outlined,
    };
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 76,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? colors.tint(colors.cyan, 42) : colors.field,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? colors.cyan : colors.border,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(color: colors.cyan.withAlpha(36), blurRadius: 16),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              color: selected ? colors.cyan : colors.muted2,
              size: 20,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: selected ? colors.cyan : colors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                height: 1.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PlateQShell extends StatefulWidget {
  const PlateQShell({super.key});

  @override
  State<PlateQShell> createState() => _PlateQShellState();
}

class _PlateQShellState extends State<PlateQShell> {
  void _selectNavigationIndex(AppState state, int index) {
    switch (index) {
      case 0:
        state.go(AppSection.dashboard);
        break;
      case 1:
        state.go(AppSection.search);
        break;
      case 2:
        state.go(AppSection.scanner);
        break;
      case 3:
        state.go(AppSection.history);
        break;
      case 4:
        _showMoreDrawer(context);
        break;
    }
  }

  void _showMoreDrawer(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _MoreDrawerSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    final size = MediaQuery.sizeOf(context);
    final wideLayout = size.width >= 900;
    return Scaffold(
      body: DecoratedBox(
        decoration: BoxDecoration(color: colors.bg),
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              const _TrackTopHeader(),
              Expanded(
                child: wideLayout
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const _TrackSidebar(),
                          Expanded(
                            child: _TrackMainPane(
                              bottomPadding: 24,
                              child: _SectionBody(section: state.section),
                            ),
                          ),
                        ],
                      )
                    : _TrackMainPane(
                        bottomPadding: 16,
                        child: _SectionBody(section: state.section),
                      ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: wideLayout
          ? null
          : _TrackBottomNav(onDestinationSelected: (index) {
              _selectNavigationIndex(state, index);
            }),
    );
  }
}

class _TrackTopHeader extends StatelessWidget {
  const _TrackTopHeader();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    final compact = MediaQuery.sizeOf(context).width < 430;
    return Container(
      height: 58,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
      decoration: BoxDecoration(
        color: colors.panel,
        border: Border(bottom: BorderSide(color: colors.cyanBorder)),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => state.go(AppSection.dashboard),
              child: Row(
                children: [
                  Container(
                    width: compact ? 36 : 40,
                    height: compact ? 36 : 40,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: colors.bgDeep,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colors.cyanBorder),
                      boxShadow: [
                        BoxShadow(
                          color: colors.cyan.withAlpha(34),
                          blurRadius: 18,
                        ),
                      ],
                    ),
                    child: Image.asset('public/logo.png', fit: BoxFit.cover),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TRACK',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                            height: 1,
                          ),
                        ),
                        if (!compact)
                          Text(
                            state.t('appSubName'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.muted,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              height: 1.25,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          _HeaderControl(
            compact: compact,
            tooltip: '${state.t('languageSetting')}: ${state.language.code}',
            onPressed: state.toggleLanguage,
            child: compact
                ? Icon(Icons.language, size: 16, color: colors.cyan)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.language, size: 16, color: colors.cyan),
                      const SizedBox(width: 5),
                      Text(
                        state.language.code,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
          ),
          SizedBox(width: compact ? 6 : 8),
          _HeaderControl(
            compact: compact,
            tooltip: state.t('themeSetting'),
            onPressed: state.toggleTheme,
            child: Icon(
              state.themeChoice == AppThemeChoice.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              size: 16,
              color: state.themeChoice == AppThemeChoice.dark
                  ? colors.amber
                  : colors.cyan,
            ),
          ),
          SizedBox(width: compact ? 6 : 8),
          _HeaderControl(
            compact: compact,
            tooltip: state.t('navProfile'),
            onPressed: () => state.go(AppSection.profile),
            child: Icon(
              Icons.person_outline,
              size: 16,
              color: colors.cyan,
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 8),
            _HeaderControl(
              tooltip: state.t('navLogout'),
              onPressed: state.logout,
              child: Icon(
                Icons.logout,
                size: 16,
                color: colors.red,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderControl extends StatelessWidget {
  const _HeaderControl({
    required this.tooltip,
    required this.onPressed,
    required this.child,
    this.compact = false,
  });

  final String tooltip;
  final VoidCallback onPressed;
  final Widget child;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onPressed,
        child: Container(
          width: compact ? 36 : null,
          height: compact ? 36 : 36,
          constraints: const BoxConstraints(minWidth: 36),
          padding: compact
              ? EdgeInsets.zero
              : const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: colors.panelSoft,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.border),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class _TrackMainPane extends StatelessWidget {
  const _TrackMainPane({
    required this.child,
    required this.bottomPadding,
  });

  final Widget child;
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1480),
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, bottomPadding),
          child: child,
        ),
      ),
    );
  }
}

class TrackPageList extends StatelessWidget {
  const TrackPageList({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(bottom: compact ? 28 : 10),
      children: children,
    );
  }
}

class TrackFilterRow extends StatelessWidget {
  const TrackFilterRow({
    super.key,
    required this.children,
    this.spacing = 8,
    this.minTwoColumnWidth = 300,
  });

  final List<Widget> children;
  final double spacing;
  final double minTwoColumnWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final twoColumn = children.length > 1 && width >= minTwoColumnWidth;
        final itemWidth = twoColumn ? (width - spacing) / 2 : width;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(
                width: itemWidth,
                child: child,
              ),
          ],
        );
      },
    );
  }
}

class _TrackBottomNav extends StatelessWidget {
  const _TrackBottomNav({required this.onDestinationSelected});

  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    final isMalay = state.language == AppLanguage.bm;
    final items = [
      _NavItemData(
        label: state.t('navDashboard'),
        shortLabel: isMalay ? 'Papan' : 'Home',
        icon: Icons.dashboard_outlined,
        section: AppSection.dashboard,
      ),
      _NavItemData(
        label: state.t('navSearch'),
        shortLabel: isMalay ? 'Cari' : 'Search',
        icon: Icons.search,
        section: AppSection.search,
      ),
      _NavItemData(
        label: state.t('navScanner'),
        shortLabel: isMalay ? 'Imbas' : 'Scan',
        icon: Icons.camera_alt_outlined,
        section: AppSection.scanner,
        scannerButton: true,
      ),
      _NavItemData(
        label: state.t('navHistory'),
        shortLabel: isMalay ? 'Audit' : 'Audit',
        icon: Icons.history,
        section: AppSection.history,
      ),
      _NavItemData(
        label: state.t('moreMenu'),
        shortLabel: state.t('moreMenu'),
        icon: Icons.more_horiz,
        section: AppSection.more,
      ),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: colors.isDark ? const Color(0xF2020617) : colors.panel,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.cyanBorder),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 30,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var index = 0; index < items.length; index += 1)
                Expanded(
                  child: _TrackBottomNavItem(
                    item: items[index],
                    active: items[index].section == state.section,
                    onTap: () => onDestinationSelected(index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackBottomNavItem extends StatelessWidget {
  const _TrackBottomNavItem({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final _NavItemData item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    if (item.scannerButton) {
      return InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.cyanStrong,
                border: Border.all(color: colors.cyanBorder),
                boxShadow: [
                  BoxShadow(color: colors.cyan.withAlpha(55), blurRadius: 14),
                ],
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: colors.bgDeep,
                ),
                child: Icon(
                  Icons.camera_alt_outlined,
                  color: colors.cyan,
                  size: 18,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.shortLabel,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.cyan,
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: active ? colors.panelSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              item.icon,
              size: 18,
              color: active ? colors.cyan : colors.muted2,
            ),
            const SizedBox(height: 5),
            Text(
              item.shortLabel,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: active ? colors.cyan : colors.muted,
                fontSize: 10,
                fontWeight: active ? FontWeight.w900 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackSidebar extends StatelessWidget {
  const _TrackSidebar();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    final items = _moreNavItems(state, includeMain: true);
    return Container(
      width: 256,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.isDark ? const Color(0xCC020617) : colors.panel,
        border: Border(right: BorderSide(color: colors.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: Text(
              state.t('navMenuHeader').toUpperCase(),
              style: TextStyle(
                color: colors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          for (final item in items)
            _SidebarButton(
              item: item,
              active: item.section == state.section,
              onTap: () => state.go(item.section),
            ),
        ],
      ),
    );
  }
}

class _SidebarButton extends StatelessWidget {
  const _SidebarButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final _NavItemData item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: active ? colors.tint(colors.cyan, 34) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: active ? colors.cyanBorder : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(
                item.icon,
                color: active ? colors.cyan : colors.muted,
                size: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? colors.cyan : colors.muted,
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoreDrawerSheet extends StatelessWidget {
  const _MoreDrawerSheet();

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    final items = _moreNavItems(state);
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        decoration: BoxDecoration(
          color: colors.panelSolid,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(top: BorderSide(color: colors.cyanBorder)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    state.t('moreMenu').toUpperCase(),
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 2.6,
              children: [
                for (final item in items)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.of(context).pop();
                      state.go(item.section);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: item.section == state.section
                            ? colors.tint(colors.cyan, 34)
                            : colors.panelSoft,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: item.section == state.section
                              ? colors.cyanBorder
                              : colors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(item.icon, color: colors.cyan, size: 18),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              item.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.text,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                state.logout();
              },
              icon: const Icon(Icons.logout, color: TrackColors.red),
              label: Text(state.t('navLogout')),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItemData {
  const _NavItemData({
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.section,
    this.scannerButton = false,
  });

  final String label;
  final String shortLabel;
  final IconData icon;
  final AppSection section;
  final bool scannerButton;
}

List<_NavItemData> _moreNavItems(AppState state, {bool includeMain = false}) {
  final items = <_NavItemData>[
    if (includeMain) ...[
      _NavItemData(
        label: state.t('navDashboard'),
        shortLabel: state.t('navDashboard'),
        icon: Icons.dashboard_outlined,
        section: AppSection.dashboard,
      ),
      _NavItemData(
        label: state.t('navScanner'),
        shortLabel: state.t('navScanner'),
        icon: Icons.camera_alt_outlined,
        section: AppSection.scanner,
      ),
      _NavItemData(
        label: state.t('navSearch'),
        shortLabel: state.t('navSearch'),
        icon: Icons.search,
        section: AppSection.search,
      ),
      _NavItemData(
        label: state.t('navHistory'),
        shortLabel: state.t('navHistory'),
        icon: Icons.history,
        section: AppSection.history,
      ),
    ],
    _NavItemData(
      label: state.t('navVehicles'),
      shortLabel: state.t('navVehicles'),
      icon: Icons.directions_car,
      section: AppSection.vehicles,
    ),
    if (state.canManageUsers)
      _NavItemData(
        label: state.t('navUsers'),
        shortLabel: state.t('navUsers'),
        icon: Icons.people_alt_outlined,
        section: AppSection.users,
      ),
    _NavItemData(
      label: state.t('navSettings'),
      shortLabel: state.t('navSettings'),
      icon: Icons.settings_outlined,
      section: AppSection.settings,
    ),
    _NavItemData(
      label: state.t('navProfile'),
      shortLabel: state.t('navProfile'),
      icon: Icons.person_outline,
      section: AppSection.profile,
    ),
  ];
  return items;
}

class _SectionBody extends StatelessWidget {
  const _SectionBody({required this.section});

  final AppSection section;

  @override
  Widget build(BuildContext context) {
    switch (section) {
      case AppSection.dashboard:
        return const DashboardScreen();
      case AppSection.search:
        return const SearchScreen();
      case AppSection.scanner:
        return const ScannerScreen();
      case AppSection.history:
        return const HistoryScreen();
      case AppSection.more:
        return const MoreScreen(showHeader: true);
      case AppSection.vehicles:
        return const VehiclesScreen();
      case AppSection.users:
        return const UsersScreen();
      case AppSection.settings:
        return const SettingsScreen();
      case AppSection.profile:
        return const ProfileScreen();
    }
  }
}

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final activeCases = state.vehicles
        .where((vehicle) => vehicle.status == VehicleStatus.active)
        .length;
    final visibleHistory = state.visibleHistory;
    final detections =
        visibleHistory.where((log) => log.type == 'DETECTION').length;
    final searches = visibleHistory.where((log) => log.type == 'SEARCH').length;
    final recent = visibleHistory.take(5).toList();
    final showQuickNav = MediaQuery.sizeOf(context).width >= 600;

    return TrackPageList(
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.55,
          children: [
            StatTile(
                label: state.t('totalVehicles'),
                value: '${state.vehicles.length}',
                icon: Icons.directions_car),
            StatTile(
                label: state.t('activeCases'),
                value: '$activeCases',
                icon: Icons.shield_outlined),
            StatTile(
                label: state.t('todayScans'),
                value: '$detections',
                icon: Icons.camera_alt_outlined),
            StatTile(
                label: state.t('manualSearches'),
                value: '$searches',
                icon: Icons.search),
          ],
        ),
        const SizedBox(height: 12),
        if (showQuickNav) ...[
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTitle(
                    icon: Icons.camera_alt_outlined,
                    title: state.t('quickNav')),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _DashboardActionButton(
                      icon: Icons.camera_alt_outlined,
                      label: state.t('openScannerBtn'),
                      tone: TrackColors.cyan,
                      onTap: () => state.go(AppSection.scanner),
                    ),
                    _DashboardActionButton(
                      icon: Icons.search,
                      label: state.t('searchPlateBtn'),
                      tone: TrackColors.cyan,
                      onTap: () => state.go(AppSection.search),
                    ),
                    _DashboardActionButton(
                      icon: Icons.directions_car,
                      label: state.t('vehiclesRepoBtn'),
                      tone: TrackColors.purple,
                      onTap: () => state.go(AppSection.vehicles),
                    ),
                    _DashboardActionButton(
                      icon: Icons.history,
                      label: state.t('auditHistoryBtn'),
                      tone: TrackColors.emerald,
                      onTap: () => state.go(AppSection.history),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                  icon: Icons.history, title: state.t('recentMatchesTitle')),
              const SizedBox(height: 8),
              for (final log in recent) HistoryListTile(log: log),
            ],
          ),
        ),
      ],
    );
  }
}

class _DashboardActionButton extends StatelessWidget {
  const _DashboardActionButton({
    required this.icon,
    required this.label,
    required this.tone,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    final effectiveTone = tone == TrackColors.cyan
        ? colors.cyan
        : tone == TrackColors.emerald
            ? colors.emerald
            : tone == TrackColors.purple
                ? colors.purple
                : tone;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: tone == TrackColors.cyan
              ? colors.tint(colors.cyan, 34)
              : colors.field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: tone == TrackColors.cyan ? colors.cyanBorder : colors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: effectiveTone, size: 18),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.text,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _query = TextEditingController();
  SearchResult? _result;
  SearchScope _scope = SearchScope.all;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    final result =
        AppScope.of(context).searchVehicles(_query.text, scope: _scope);
    setState(() => _result = result);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    return TrackPageList(
      children: [
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(icon: Icons.search, title: state.t('searchTitle')),
              const SizedBox(height: 12),
              TextField(
                controller: _query,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(
                  color: colors.cyan,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: state.t('searchPlaceholder'),
                ),
                onSubmitted: (_) => _search(),
              ),
              if (!compact) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final scope in SearchScope.values)
                      TrackOptionButton(
                        selected: _scope == scope,
                        label: _searchScopeLabel(state, scope),
                        compact: true,
                        onPressed: () => setState(() => _scope = scope),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _search,
                icon: const Icon(Icons.search),
                label: Text(state.t('searchBtn')),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (_result != null) SearchResultPanel(result: _result!),
      ],
    );
  }
}

class SearchResultPanel extends StatelessWidget {
  const SearchResultPanel({super.key, required this.result});

  final SearchResult result;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    if (result.exactMatch == null && result.possibleMatches.isEmpty) {
      return SectionCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.tint(colors.cyan, 34),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.cyanBorder),
              ),
              child: Icon(Icons.check_circle_outline, color: colors.cyan),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    state.t('noMatchTitle'),
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.t('noMatchDesc'),
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (result.exactMatch != null) ...[
            VehicleMatchCard(vehicle: result.exactMatch!, tone: 'EXACT'),
            _SearchActionPanel(vehicle: result.exactMatch!),
          ],
          for (final vehicle in result.possibleMatches)
            VehicleMatchCard(vehicle: vehicle, tone: 'POSSIBLE'),
        ],
      ),
    );
  }
}

class _SearchActionPanel extends StatelessWidget {
  const _SearchActionPanel({required this.vehicle});

  final Vehicle vehicle;

  void _mark(
    BuildContext context, {
    required VehicleStatus status,
    required String action,
    required String details,
    required String statusMatch,
  }) {
    final state = AppScope.of(context);
    state.setVehicleStatus(vehicle, status);
    state.addHistoryLog(
      type: 'SEARCH',
      action: '$action: ${vehicle.plate}',
      plate: vehicle.plate,
      details: details,
      statusMatch: statusMatch,
      note: details,
    );
    _showSnack(context, '$action recorded for ${vehicle.plate}');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            state.t('actionsHeader').toUpperCase(),
            style: TextStyle(
              color: colors.muted,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              TrackOptionButton(
                selected: vehicle.status == VehicleStatus.flagged,
                label: state.t('statusFlagged'),
                icon: Icons.bookmark_added_outlined,
                tone: TrackColors.red,
                onPressed: () => _mark(
                  context,
                  status: VehicleStatus.flagged,
                  action: 'Tanda Tindakan',
                  details:
                      'Marked for action from native plate search by ${state.role.code}',
                  statusMatch: 'EXACT',
                ),
              ),
              TrackOptionButton(
                selected: vehicle.status == VehicleStatus.pending,
                label: state.t('statusPending'),
                icon: Icons.pending_actions_outlined,
                tone: TrackColors.amber,
                onPressed: () => _mark(
                  context,
                  status: VehicleStatus.pending,
                  action: 'Dalam Semakan',
                  details:
                      'Marked as pending review from native plate search by ${state.role.code}',
                  statusMatch: 'POSSIBLE',
                ),
              ),
              TrackOptionButton(
                selected: vehicle.status == VehicleStatus.cleared,
                label: state.t('statusCleared'),
                icon: Icons.check_circle_outline,
                tone: TrackColors.emerald,
                onPressed: () => _mark(
                  context,
                  status: VehicleStatus.cleared,
                  action: 'Kes Selesai',
                  details:
                      'Marked as cleared from native plate search by ${state.role.code}',
                  statusMatch: 'NONE',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final NativeAnprBridge _bridge = NativeAnprBridge();
  StreamSubscription<AnprEvent>? _subscription;
  List<NativeCameraDevice> _nativeCameras = const [];
  List<AnprTrack> _tracks = const [];
  final Map<String, Map<String, OcrVote>> _ocrVotes = {};
  final Map<String, String> _trackPlates = {};
  final Map<String, DateTime> _alertCooldowns = {};
  AnprAlert? _latestAlert;
  List<NativeModelAssetStatus> _modelAssets = const [];
  String? _selectedCameraId;
  String _runtimeState = 'UNINITIALIZED';
  String _deviceTier = 'AUTO';
  String _detectorProvider = 'NONE';
  String _ocrProvider = 'NONE';
  String _environmentProvider = 'NONE';
  String _plateQualityProvider = 'NONE';
  String _environmentLabel = 'GOOD_CONDITION';
  String _plateQualityClass = 'UNKNOWN';
  String _status = 'Native scanner bridge idle';
  String _latestOcrStatus = 'Waiting for OCR';
  double _cameraFps = 0;
  double _detectorFps = 0;
  double _environmentConfidence = 0;
  double _plateQualityScore = 0;
  int _ocrQueueDepth = 0;
  bool _scanning = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _subscription =
        _bridge.events.listen(_handleEvent, onError: _handleBridgeError);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _bridge.dispose().ignore();
    super.dispose();
  }

  void _handleEvent(AnprEvent event) {
    if (!mounted) return;
    final state = AppScope.of(context);
    AnprAlert? alertToLog;
    setState(() {
      if (event is RuntimeAnprEvent) {
        _runtimeState = event.runtimeState;
        _deviceTier = event.deviceTier;
        _detectorProvider = event.detectorProvider;
        _ocrProvider = event.ocrProvider;
        _environmentProvider = event.environmentProvider;
        _plateQualityProvider = event.plateQualityProvider;
        _environmentLabel = event.environmentLabel;
        _environmentConfidence = event.environmentConfidence;
        _plateQualityClass = event.plateQualityClass;
        _plateQualityScore = event.plateQualityScore;
        _cameraFps = event.cameraFps;
        _detectorFps = event.detectorFps;
        _ocrQueueDepth = event.ocrQueueDepth;
        _status = event.runtimeState;
      } else if (event is TrackUpdateAnprEvent) {
        _tracks = event.tracks;
      } else if (event is OcrAnprEvent) {
        final alert = _handleOcrEvent(event, state);
        if (alert != null) {
          _latestAlert = alert;
          alertToLog = alert;
        }
      } else if (event is MatchAlertAnprEvent) {
        _latestAlert = event.alert;
        alertToLog = event.alert;
      } else if (event is ErrorAnprEvent) {
        _status = event.message;
      }
    });
    final alert = alertToLog;
    if (alert != null) {
      state.addHistoryLog(
        type: 'DETECTION',
        action: 'Live Scan: ${alert.plate}',
        plate: alert.plate,
        details: '${alert.matchType} match from ${alert.cameraLabel}',
        statusMatch: alert.matchType,
        cameraName: alert.cameraLabel,
        note: _alertEvidenceNote(alert.evidence),
      );
      if (state.settings.soundAlerts) {
        HapticFeedback.mediumImpact().ignore();
        SystemSound.play(SystemSoundType.alert);
      }
    }
  }

  AnprAlert? _handleOcrEvent(OcrAnprEvent event, AppState state) {
    final rawPlate = event.normalizedPlate.isNotEmpty
        ? event.normalizedPlate
        : event.rawText;
    final characterConfidences = event.characterConfidences
        .where((item) => item.char.isNotEmpty)
        .map(
          (item) => CharacterConfidence(
            char: item.char,
            confidence: item.confidence,
            position: item.position,
          ),
        )
        .toList();
    final correction = correctMalaysianPlateOcr(
      rawPlate,
      options: SpecialPlateCorrectionOptions(
        ocrConfidence: event.confidence,
        characterConfidences: characterConfidences,
      ),
    );
    final normalized = correction.normalized.isNotEmpty
        ? correction.normalized
        : normalizePlate(rawPlate);
    if (normalized.isEmpty) {
      _latestOcrStatus = '${event.trackId}: no readable plate';
      return null;
    }

    final votes = Map<String, OcrVote>.from(_ocrVotes[event.trackId] ?? {});
    final previous = votes[normalized];
    votes[normalized] = OcrVote(
      count: (previous?.count ?? 0) + 1,
      totalConfidence: (previous?.totalConfidence ?? 0) + event.confidence,
    );
    _ocrVotes[event.trackId] = votes;

    final consensus = evaluateConsensus(
      votes,
      requiredVotes: state.settings.consensusVotes,
      minConfidence: state.settings.ocrConfidence,
    );
    final displayPlate = consensus.displayPlate.isNotEmpty
        ? consensus.displayPlate
        : formatDisplayPlate(normalized);
    _trackPlates[event.trackId] = displayPlate;
    _latestOcrStatus =
        '${event.trackId}: $displayPlate ${(event.confidence * 100).round()}% '
        '(${consensus.voteCount}/${state.settings.consensusVotes})';

    if (!consensus.isStabilized) return null;

    final match = evaluateDatabaseMatch(
      consensus.normalizedPlate,
      consensus.confidence,
      state.vehicles,
      characterConfidences: characterConfidences,
      minConfidenceThreshold: state.settings.ocrConfidence,
    );
    if (match.matchType != MatchType.exact &&
        match.matchType != MatchType.possible) {
      return null;
    }

    final cooldownKey =
        '${event.trackId}:${match.normalizedPlate}:${match.matchType.code}';
    final now = DateTime.now().toUtc();
    final lastAlert = _alertCooldowns[cooldownKey];
    if (lastAlert != null && now.difference(lastAlert).inSeconds < 45) {
      return null;
    }
    _alertCooldowns[cooldownKey] = now;

    final matchedVehicle = match.matchedVehicle ??
        _firstWhereOrNull(match.possibleMatches, (_) => true);
    final track =
        _firstWhereOrNull(_tracks, (item) => item.trackId == event.trackId);
    return AnprAlert(
      trackId: event.trackId,
      plate: match.normalizedPlate,
      confidence: match.confidence,
      matchType: match.matchType.code,
      cameraLabel: _currentCameraLabel(),
      reason: match.reason,
      vehicle: matchedVehicle == null
          ? const <String, dynamic>{}
          : _vehicleToAlertMap(matchedVehicle),
      evidence: <String, dynamic>{
        'vehicleImagePath': event.vehicleImagePath,
        'plateImagePath': event.plateImagePath,
        'plateEnhancedImagePath': event.plateEnhancedImagePath,
        'plateBinaryImagePath': event.plateBinaryImagePath,
        'plateTopLineImagePath': event.plateTopLineImagePath,
        'plateBottomLineImagePath': event.plateBottomLineImagePath,
        'plateInnerTextImagePath': event.plateInnerTextImagePath,
        'plateCropWidth': event.plateCropWidth,
        'plateCropHeight': event.plateCropHeight,
        'preprocessingVariant': event.preprocessingVariant,
        'preprocessingVariants': event.preprocessingVariants,
        'capturedAt': event.timestamp.toUtc().toIso8601String(),
        'qualityScore': track?.qualityScore ?? _plateQualityScore,
        'detectorConfidence': track?.detectorConfidence ?? 0,
        'ocrConfidence': consensus.confidence,
        'ocrProvider':
            event.provider.isNotEmpty ? event.provider : _ocrProvider,
        'environment': _environmentLabel,
        'qualityClass': track?.qualityClass ?? _plateQualityClass,
      },
    );
  }

  String _currentCameraLabel() {
    return _firstWhereOrNull(
          _nativeCameras,
          (camera) => camera.id == _selectedCameraId,
        )?.label ??
        'Native Scanner';
  }

  void _handleBridgeError(Object error) {
    if (!mounted) return;
    setState(() {
      _status = _friendlyBridgeError(error);
      _scanning = false;
    });
  }

  Future<NativeRuntimeStatus> _refreshNativeRuntime(AppState state) async {
    final status = await _bridge.initialize();
    final cameras = await _bridge.listCameras();
    final preferredCameraId = state.selectedCameraId;
    final defaultCameraId =
        _firstWhereOrNull(cameras, (camera) => camera.isDefault)?.id ??
            (cameras.isNotEmpty ? cameras.first.id : null);
    final nextCameraId = cameras.any((camera) => camera.id == preferredCameraId)
        ? preferredCameraId
        : defaultCameraId;
    setState(() {
      _runtimeState = status.runtimeState;
      _deviceTier = status.deviceTier;
      _detectorProvider = status.detectorProvider;
      _ocrProvider = status.ocrProvider;
      _environmentProvider = status.environmentProvider;
      _plateQualityProvider = status.plateQualityProvider;
      _modelAssets = status.modelAssets;
      _nativeCameras = cameras;
      _selectedCameraId = nextCameraId;
      _status = 'Native runtime ${status.runtimeState}';
    });
    state.setSelectedCameraId(nextCameraId);
    if (nextCameraId != null) {
      await _bridge.selectCamera(nextCameraId);
    }
    return status;
  }

  bool get _requiredModelsReady {
    final required = _modelAssets.where((asset) => asset.required).toList();
    return required.isNotEmpty && required.every((asset) => asset.nativeReady);
  }

  bool _runtimeCanRunRealScanner(NativeRuntimeStatus status) {
    return status.requiredModelAssetsReady &&
        status.detectorProvider.startsWith('CPU_ONNX') &&
        status.detectorProvider != 'CPU_ONNX_ERROR' &&
        status.ocrProvider.startsWith('CPU_ONNX_PP_OCR') &&
        status.ocrProvider != 'CPU_ONNX_PP_OCR_ERROR';
  }

  String _modelReadinessMessage(NativeRuntimeStatus status) {
    final missing = status.missingRequiredModelAssets
        .map((asset) => asset.id)
        .where((id) => id.isNotEmpty)
        .join(', ');
    if (missing.isNotEmpty) {
      return 'Required native ANPR model assets missing: $missing';
    }
    final warning =
        status.warnings.isNotEmpty ? ' ${status.warnings.first}' : '';
    return 'Native detector/OCR is not ready. Initialize real ONNX models before scanning.$warning';
  }

  Future<void> _initialize() async {
    final state = AppScope.of(context);
    setState(() => _busy = true);
    try {
      final status = await _refreshNativeRuntime(state);
      if (!_runtimeCanRunRealScanner(status)) {
        setState(() => _status = _modelReadinessMessage(status));
      }
    } catch (error) {
      setState(() => _status = _friendlyBridgeError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    final state = AppScope.of(context);
    final cameraId = _selectedCameraId ?? 'native-back';
    state.setSelectedCameraId(cameraId);
    setState(() {
      _busy = true;
      _status = 'Preparing real native ANPR models';
    });
    try {
      NativeRuntimeStatus? status;
      if (!_requiredModelsReady ||
          !_detectorProvider.startsWith('CPU_ONNX') ||
          !_ocrProvider.startsWith('CPU_ONNX_PP_OCR')) {
        status = await _refreshNativeRuntime(state);
      }
      if (status != null && !_runtimeCanRunRealScanner(status)) {
        final readinessStatus = status;
        setState(() {
          _status = _modelReadinessMessage(readinessStatus);
          _scanning = false;
        });
        return;
      }
      final selectedCamera = _selectedCameraId ?? cameraId;
      if (selectedCamera.isEmpty) {
        setState(() {
          _status = 'No native camera is available for scanning.';
          _scanning = false;
        });
        return;
      }
      setState(() => _status = 'Starting native scanner');
      await _bridge.startScanning(
        cameraId: selectedCamera,
        detectionThreshold: state.settings.detectionConfidence,
        recognitionThreshold: state.settings.ocrConfidence,
        consensusVotes: state.settings.consensusVotes,
        maxTracks: state.settings.maxTracks,
        maxOcrConcurrency: state.settings.maxOcrConcurrency,
        enableSpecialSeries: state.settings.enableSpecialSeries,
      );
      setState(() {
        _ocrVotes.clear();
        _trackPlates.clear();
        _alertCooldowns.clear();
        _latestOcrStatus = 'Waiting for OCR';
        _scanning = true;
        _runtimeState = 'SCANNING';
        _status = 'Scanning selected camera';
      });
    } catch (error) {
      setState(() {
        _status = _friendlyBridgeError(error);
        _scanning = false;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    setState(() => _busy = true);
    try {
      await _bridge.stopScanning();
    } catch (_) {
      // Stop remains idempotent in the UI; native code owns cleanup details.
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _scanning = false;
          _runtimeState = 'READY';
          _status = 'Scanner stopped';
          _latestOcrStatus = 'Waiting for OCR';
          _tracks = const [];
          _ocrVotes.clear();
          _trackPlates.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    final selectedCamera = _firstWhereOrNull(
        _nativeCameras, (camera) => camera.id == _selectedCameraId);
    final cameraLabel = selectedCamera?.label ?? 'Rear Camera';
    final requiredModelCount =
        _modelAssets.where((asset) => asset.required).length;
    final readyRequiredModelCount = _modelAssets
        .where((asset) => asset.required && asset.nativeReady)
        .length;
    final missingOptionalModelCount = _modelAssets
        .where((asset) => !asset.required && !asset.available)
        .length;

    return TrackPageList(
      children: [
        SectionTitle(
            icon: Icons.camera_alt_outlined,
            title: state.t('liveScannerTitle')),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _busy ? null : (_scanning ? _stop : _start),
                icon: Icon(_scanning ? Icons.stop : Icons.play_arrow),
                label: Text(
                    _scanning ? 'Stop Scanning' : state.t('openScannerBtn')),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Initialize native runtime',
              onPressed: _busy ? null : _initialize,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_nativeCameras.isNotEmpty)
          TrackDropdownField<String>(
            value: _selectedCameraId,
            label: 'Select Camera',
            icon: Icons.videocam_outlined,
            items: [
              for (final camera in _nativeCameras)
                DropdownMenuItem(
                    value: camera.id,
                    child: Text('${camera.label} (${camera.facing})')),
            ],
            onChanged: _scanning
                ? null
                : (value) {
                    setState(() => _selectedCameraId = value);
                    state.setSelectedCameraId(value);
                    if (value != null) _bridge.selectCamera(value).ignore();
                  },
          ),
        const SizedBox(height: 10),
        CameraSurface(
            scanning: _scanning, tracks: _tracks, alert: _latestAlert),
        if (!compact) ...[
          const SizedBox(height: 10),
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionTitle(icon: Icons.memory, title: _status),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    MetricChip(
                        label: state.t('cameraPreview'), value: cameraLabel),
                    MetricChip(label: 'Runtime', value: _runtimeState),
                    MetricChip(label: 'Tier', value: _deviceTier),
                    if (_modelAssets.isNotEmpty)
                      MetricChip(
                        label: 'Models',
                        value: '$readyRequiredModelCount/$requiredModelCount',
                      ),
                    MetricChip(label: 'Detector', value: _detectorProvider),
                    MetricChip(label: 'OCR', value: _ocrProvider),
                    MetricChip(label: 'OCR State', value: _latestOcrStatus),
                    MetricChip(
                        label: state.t('cameraFps'),
                        value: _cameraFps.toStringAsFixed(1)),
                    MetricChip(
                        label: state.t('detectionFps'),
                        value: _detectorFps.toStringAsFixed(1)),
                    MetricChip(
                        label: 'Environment',
                        value:
                            '$_environmentLabel ${(_environmentConfidence * 100).round()}%'),
                    MetricChip(
                        label: 'Quality',
                        value:
                            '$_plateQualityClass ${(_plateQualityScore * 100).round()}%'),
                    MetricChip(
                        label: 'Env Provider', value: _environmentProvider),
                    MetricChip(
                        label: 'Quality Provider',
                        value: _plateQualityProvider),
                    MetricChip(label: 'OCR Queue', value: '$_ocrQueueDepth'),
                    if (missingOptionalModelCount > 0)
                      MetricChip(
                        label: 'Optional Models',
                        value: '$missingOptionalModelCount missing',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                  icon: Icons.list_alt, title: state.t('recentDetectionList')),
              const SizedBox(height: 8),
              if (_tracks.isEmpty)
                Text('Waiting for native track events.',
                    style: TextStyle(color: colors.muted))
              else
                for (final track in _tracks)
                  TrackEventCard(
                    track: track,
                    displayPlate: _trackPlates[track.trackId] ??
                        (track.plate.isEmpty ? track.trackId : track.plate),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class CameraSurface extends StatelessWidget {
  const CameraSurface({
    super.key,
    required this.scanning,
    required this.tracks,
    required this.alert,
  });

  final bool scanning;
  final List<AnprTrack> tracks;
  final AnprAlert? alert;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return AspectRatio(
      aspectRatio: 16 / 10,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.bgDeep,
            border: Border.all(color: colors.cyanBorder),
          ),
          child: ColoredBox(
            color: colors.bgDeep,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    if (scanning)
                      const PlatformCameraPreview()
                    else
                      const CameraIdleView(),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: colors.cyan.withAlpha(48),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                    for (final track in tracks)
                      Positioned(
                        left: track.bbox.x * constraints.maxWidth,
                        top: track.bbox.y * constraints.maxHeight,
                        width: track.bbox.width * constraints.maxWidth,
                        height: track.bbox.height * constraints.maxHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border.all(
                                color: _trackColor(track.matchType), width: 2),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    if (alert != null) AlertOverlay(alert: alert!),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class PlatformCameraPreview extends StatelessWidget {
  const PlatformCameraPreview({super.key});

  @override
  Widget build(BuildContext context) {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return const AndroidView(viewType: 'plateq.anpr_camera_preview');
      case TargetPlatform.iOS:
        return const UiKitView(viewType: 'plateq.anpr_camera_preview');
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        return const CameraIdleView();
    }
  }
}

class CameraIdleView extends StatelessWidget {
  const CameraIdleView({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.camera_alt_outlined, color: colors.cyan, size: 44),
          const SizedBox(height: 8),
          Text('Native camera preview',
              style:
                  TextStyle(color: colors.text, fontWeight: FontWeight.w900)),
          const SizedBox(height: 4),
          Text('Tap start scanning to open the native camera.',
              style: TextStyle(color: colors.muted)),
        ],
      ),
    );
  }
}

class AlertOverlay extends StatelessWidget {
  const AlertOverlay({super.key, required this.alert});

  final AnprAlert alert;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Container(
        margin: const EdgeInsets.all(10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xE6991111),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
          boxShadow: const [
            BoxShadow(color: Color(0xAA450A0A), blurRadius: 20),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(alert.plate,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 18)),
                  Text(
                      '${alert.matchType} · ${(alert.confidence * 100).round()}% · ${alert.cameraLabel}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class VehiclesScreen extends StatefulWidget {
  const VehiclesScreen({super.key});

  @override
  State<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends State<VehiclesScreen> {
  final TextEditingController _query = TextEditingController();
  VehicleStatus? _status;
  VehiclePriority? _priority;
  int _page = 0;
  final int _pageSize = 12;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _openEditor({Vehicle? vehicle}) async {
    final state = AppScope.of(context);
    final result = await showDialog<Vehicle>(
      context: context,
      builder: (_) => VehicleDraftDialog(
          vehicle: vehicle, nextId: _nextVehicleId(state.vehicles)),
    );
    if (!mounted || result == null) return;
    state.upsertVehicle(result);
    _showSnack(context, vehicle == null ? 'Vehicle added' : 'Vehicle updated');
  }

  Future<void> _deleteVehicle(Vehicle vehicle) async {
    final confirmed = await _confirmAction(context, 'Delete ${vehicle.plate}?',
        'This removes the local demo repository entry.');
    if (!mounted || !confirmed) return;
    AppScope.of(context).removeVehicle(vehicle);
    _showSnack(context, 'Vehicle deleted');
  }

  Future<void> _exportVehicles(List<Vehicle> vehicles) async {
    final csv = _vehiclesToCsv(vehicles);
    final shared = await NativeShare.shareText(
      title: 'Export Vehicles CSV',
      fileName: 'plateq-vehicles.csv',
      mimeType: 'text/csv',
      text: csv,
    );
    if (!shared) {
      await Clipboard.setData(ClipboardData(text: csv));
    }
    if (!mounted) return;
    AppScope.of(context).addHistoryLog(
      type: 'DATABASE',
      action: 'Export Vehicles CSV',
      details: shared
          ? '${vehicles.length} filtered vehicles shared through native sheet'
          : '${vehicles.length} filtered vehicles copied to clipboard fallback',
      statusMatch: 'EXPORT',
    );
    _showSnack(context,
        shared ? 'Vehicle CSV shared' : 'Vehicle CSV copied as fallback');
  }

  Future<void> _importVehicles() async {
    final csv = await NativeShare.pickCsv();
    if (!mounted) return;
    if (csv == null || csv.trim().isEmpty) {
      _showSnack(context, 'No CSV selected');
      return;
    }
    final summary = AppScope.of(context).importVehiclesFromCsv(csv);
    setState(() => _page = 0);
    _showSnack(
      context,
      'Imported ${summary.imported}, updated ${summary.updated}, skipped ${summary.skipped}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    final filtered = state.vehicles.where((vehicle) {
      return _matchesVehicleFilter(vehicle, _query.text, _status, _priority);
    }).toList();
    final pageItems = _pagedItems(filtered, _page, _pageSize);
    return TrackPageList(
      children: [
        SectionTitle(
            icon: Icons.directions_car, title: state.t('manageVehiclesTitle')),
        Text(state.t('manageVehiclesSub'),
            style: TextStyle(color: colors.muted, fontSize: 12)),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _query,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  labelText: state.t('searchVehiclePlaceholder'),
                ),
                onChanged: (_) => setState(() => _page = 0),
              ),
              const SizedBox(height: 10),
              TrackFilterRow(
                children: [
                  TrackDropdownField<VehicleStatus?>(
                    value: _status,
                    label: 'Status',
                    icon: Icons.flag_outlined,
                    items: [
                      DropdownMenuItem<VehicleStatus?>(
                          value: null, child: Text(state.t('filterByStatus'))),
                      for (final status in VehicleStatus.values)
                        DropdownMenuItem<VehicleStatus?>(
                            value: status,
                            child: Text(_vehicleStatusLabel(state, status))),
                    ],
                    onChanged: (value) => setState(() {
                      _status = value;
                      _page = 0;
                    }),
                  ),
                  TrackDropdownField<VehiclePriority?>(
                    value: _priority,
                    label: state.t('priority'),
                    icon: Icons.priority_high,
                    items: [
                      const DropdownMenuItem<VehiclePriority?>(
                          value: null, child: Text('All Priority')),
                      for (final priority in VehiclePriority.values)
                        DropdownMenuItem<VehiclePriority?>(
                            value: priority,
                            child:
                                Text(_vehiclePriorityLabel(state, priority))),
                    ],
                    onChanged: (value) => setState(() {
                      _priority = value;
                      _page = 0;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (state.canManageVehicles)
                    FilledButton.icon(
                      onPressed: () => _openEditor(),
                      icon: const Icon(Icons.add),
                      label: Text(state.t('addVehicle')),
                    ),
                  if (state.canManageSystem)
                    OutlinedButton.icon(
                      onPressed: _importVehicles,
                      icon: const Icon(Icons.upload_file),
                      label: Text(state.t('importCsv')),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _exportVehicles(filtered),
                    icon: const Icon(Icons.download),
                    label: Text(state.t('exportCsv')),
                  ),
                ],
              ),
            ],
          ),
        ),
        Text('${filtered.length} / ${state.vehicles.length} vehicles',
            style: TextStyle(color: colors.muted, fontSize: 12)),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          const EmptyPanel(message: 'No vehicles match the current filters.'),
        for (final vehicle in pageItems)
          VehicleListCard(
            vehicle: vehicle,
            canEdit: state.canManageVehicles,
            onEdit: () => _openEditor(vehicle: vehicle),
            onDelete: () => _deleteVehicle(vehicle),
          ),
        if (filtered.isNotEmpty)
          PagedListControls(
            totalItems: filtered.length,
            page: _page,
            pageSize: _pageSize,
            onPageChanged: (page) => setState(() => _page = page),
          ),
      ],
    );
  }
}

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TextEditingController _query = TextEditingController();
  String? _type;
  bool _newestFirst = true;
  int _page = 0;
  final int _pageSize = 20;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _exportHistory(List<HistoryLog> history) async {
    final csv = _historyToCsv(history);
    final shared = await NativeShare.shareText(
      title: 'Export Audit History CSV',
      fileName: 'plateq-history.csv',
      mimeType: 'text/csv',
      text: csv,
    );
    if (!shared) {
      await Clipboard.setData(ClipboardData(text: csv));
    }
    if (!mounted) return;
    _showSnack(context,
        shared ? 'History CSV shared' : 'History CSV copied as fallback');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    final history = state.visibleHistory
        .where((log) => _matchesHistoryFilter(log, _query.text, _type))
        .toList()
      ..sort((a, b) => _newestFirst
          ? b.timestamp.compareTo(a.timestamp)
          : a.timestamp.compareTo(b.timestamp));
    final pageItems = _pagedItems(history, _page, _pageSize);
    final types = state.visibleHistory.map((log) => log.type).toSet().toList()
      ..sort();
    return TrackPageList(
      children: [
        SectionTitle(icon: Icons.history, title: state.t('historyTitle')),
        Text(state.t('historySub'),
            style: TextStyle(color: colors.muted, fontSize: 12)),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _query,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Filter plate, actor, action, details...',
                ),
                onChanged: (_) => setState(() => _page = 0),
              ),
              const SizedBox(height: 10),
              TrackFilterRow(
                children: [
                  TrackDropdownField<String?>(
                    value: _type,
                    label: 'Type',
                    icon: Icons.category_outlined,
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('All Types')),
                      for (final type in types)
                        DropdownMenuItem<String?>(
                            value: type, child: Text(type)),
                    ],
                    onChanged: (value) => setState(() {
                      _type = value;
                      _page = 0;
                    }),
                  ),
                  TrackOptionButton(
                    selected: _newestFirst,
                    icon: Icons.south,
                    label: 'Newest First',
                    onPressed: () => setState(() {
                      _newestFirst = !_newestFirst;
                      _page = 0;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _exportHistory(history),
                icon: const Icon(Icons.download),
                label: Text(state.t('exportCsv')),
              ),
            ],
          ),
        ),
        Text('${history.length} audit records',
            style: TextStyle(color: colors.muted, fontSize: 12)),
        const SizedBox(height: 8),
        if (history.isEmpty)
          const EmptyPanel(
              message: 'No audit records match the current filters.'),
        for (final log in pageItems) HistoryListTile(log: log),
        if (history.isNotEmpty)
          PagedListControls(
            totalItems: history.length,
            page: _page,
            pageSize: _pageSize,
            onPageChanged: (page) => setState(() => _page = page),
          ),
      ],
    );
  }
}

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final TextEditingController _query = TextEditingController();
  Role? _role;
  String? _status;
  int _page = 0;
  final int _pageSize = 10;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _openEditor({AppUser? user}) async {
    final state = AppScope.of(context);
    final result = await showDialog<AppUser>(
      context: context,
      builder: (_) => UserDraftDialog(
          user: user,
          nextId: _nextUserId(state.users),
          createdBy: state.currentUser?.id),
    );
    if (!mounted || result == null) return;
    state.upsertUser(result);
    _showSnack(context, user == null ? 'User added' : 'User updated');
  }

  Future<void> _deleteUser(AppUser user) async {
    final confirmed = await _confirmAction(context, 'Delete ${user.name}?',
        'This removes the local demo user entry.');
    if (!mounted || !confirmed) return;
    AppScope.of(context).removeUser(user);
    _showSnack(context, 'User deleted');
  }

  void _toggleUser(AppUser user) {
    final nextStatus = user.status == 'ACTIVE' ? 'DISABLED' : 'ACTIVE';
    AppScope.of(context).setUserStatus(user, nextStatus);
    _showSnack(context, 'User ${nextStatus.toLowerCase()}');
  }

  void _resetPassword(AppUser user) {
    AppScope.of(context).resetUserPassword(user);
    _showSnack(context, 'Password reset recorded');
  }

  void _viewHistory(AppUser user) {
    final state = AppScope.of(context);
    final logs = state.history
        .where((log) =>
            log.actorId == user.id ||
            log.actorName == user.name ||
            log.userRole == user.role)
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    showDialog<void>(
      context: context,
      builder: (_) => UserHistoryDialog(user: user, logs: logs),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    if (!state.canManageUsers) {
      return const PermissionPanel();
    }
    final filtered = state.users
        .where((user) => _matchesUserFilter(user, _query.text, _role, _status))
        .toList();
    final pageItems = _pagedItems(filtered, _page, _pageSize);
    final statuses = state.users.map((user) => user.status).toSet().toList()
      ..sort();
    return TrackPageList(
      children: [
        SectionTitle(
            icon: Icons.people_alt_outlined,
            title: state.t('manageUsersTitle')),
        Text(state.t('manageUsersSub'),
            style: TextStyle(color: colors.muted, fontSize: 12)),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _query,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: 'Search name, email, phone...',
                ),
                onChanged: (_) => setState(() => _page = 0),
              ),
              const SizedBox(height: 10),
              TrackFilterRow(
                children: [
                  TrackDropdownField<Role?>(
                    value: _role,
                    label: state.t('roleHeader'),
                    icon: Icons.shield_outlined,
                    items: [
                      const DropdownMenuItem<Role?>(
                          value: null, child: Text('All Roles')),
                      for (final role in Role.values)
                        DropdownMenuItem<Role?>(
                            value: role, child: Text(_roleLabel(state, role))),
                    ],
                    onChanged: (value) => setState(() {
                      _role = value;
                      _page = 0;
                    }),
                  ),
                  TrackDropdownField<String?>(
                    value: _status,
                    label: 'Status',
                    icon: Icons.verified_outlined,
                    items: [
                      const DropdownMenuItem<String?>(
                          value: null, child: Text('All Status')),
                      for (final status in statuses)
                        DropdownMenuItem<String?>(
                            value: status, child: Text(status)),
                    ],
                    onChanged: (value) => setState(() {
                      _status = value;
                      _page = 0;
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _openEditor(),
                    icon: const Icon(Icons.person_add_alt),
                    label: Text(state.t('addUser')),
                  ),
                ],
              ),
            ],
          ),
        ),
        Text('${filtered.length} / ${state.users.length} users',
            style: TextStyle(color: colors.muted, fontSize: 12)),
        const SizedBox(height: 8),
        if (filtered.isEmpty)
          const EmptyPanel(message: 'No users match the current filters.'),
        for (final user in pageItems)
          UserListCard(
            user: user,
            canDelete: state.currentUser?.id != user.id,
            onEdit: () => _openEditor(user: user),
            onToggle: () => _toggleUser(user),
            onResetPassword: () => _resetPassword(user),
            onDelete: () => _deleteUser(user),
            onViewHistory: () => _viewHistory(user),
          ),
        if (filtered.isNotEmpty)
          PagedListControls(
            totalItems: filtered.length,
            page: _page,
            pageSize: _pageSize,
            onPageChanged: (page) => setState(() => _page = page),
          ),
      ],
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    final settings = state.settings;
    return TrackPageList(
      children: [
        SectionTitle(
            icon: Icons.settings_outlined, title: state.t('settingsTitle')),
        Text(state.t('settingsSub'),
            style: TextStyle(color: colors.muted, fontSize: 12)),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                  icon: Icons.language, title: state.t('languageSetting')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TrackOptionButton(
                      selected: state.language == AppLanguage.bm,
                      label: 'Bahasa Melayu (BM)',
                      compact: true,
                      onPressed: () => state.setLanguage(AppLanguage.bm),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TrackOptionButton(
                      selected: state.language == AppLanguage.en,
                      label: 'English (EN)',
                      compact: true,
                      onPressed: () => state.setLanguage(AppLanguage.en),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SectionTitle(
                  icon: Icons.palette_outlined, title: state.t('themeSetting')),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TrackOptionButton(
                      selected: state.themeChoice == AppThemeChoice.dark,
                      icon: Icons.dark_mode_outlined,
                      label: state.t('darkModeLabel'),
                      compact: true,
                      onPressed: () =>
                          state.setThemeChoice(AppThemeChoice.dark),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TrackOptionButton(
                      selected: state.themeChoice == AppThemeChoice.light,
                      icon: Icons.light_mode_outlined,
                      label: state.t('lightModeLabel'),
                      tone: TrackColors.amber,
                      compact: true,
                      onPressed: () =>
                          state.setThemeChoice(AppThemeChoice.light),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TrackSwitchTile(
                icon: Icons.volume_up_outlined,
                title: state.t('soundAlertSetting'),
                subtitle: state.t('soundAlertSub'),
                value: settings.soundAlerts,
                onChanged: (value) =>
                    state.updateSettings(settings.copyWith(soundAlerts: value)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                  icon: Icons.info_outline, title: state.t('versionInfo')),
              const SizedBox(height: 12),
              _InfoRow(label: state.t('softwareNameLabel'), value: 'TRACK'),
              _InfoRow(
                  label: state.t('engineVersionLabel'), value: 'v2.4.0-native'),
              const _InfoRow(
                  label: 'Native Status', value: 'Flutter Android/iOS'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        MoreScreen(showHeader: true),
      ],
    );
  }
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _oldPassword = TextEditingController();
  final TextEditingController _newPassword = TextEditingController();
  String? _loadedUserId;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _oldPassword.dispose();
    _newPassword.dispose();
    super.dispose();
  }

  void _syncUser(AppUser? user) {
    if (user == null || _loadedUserId == user.id) return;
    _loadedUserId = user.id;
    _name.text = user.name;
    _email.text = user.email;
    _phone.text = user.phone;
  }

  void _saveProfile() {
    AppScope.of(context).updateCurrentUser(
      name: _name.text.trim(),
      email: _email.text.trim(),
      phone: _phone.text.trim(),
    );
    _showSnack(context, 'Profile updated');
  }

  void _changePassword() {
    if (_oldPassword.text.isEmpty || _newPassword.text.length < 6) {
      _showSnack(context,
          'Enter current password and a new password with at least 6 characters');
      return;
    }
    AppScope.of(context).addHistoryLog(
      type: 'USER',
      action: 'Profile Password Change',
      details: 'Password change recorded for current demo user',
      statusMatch: 'PASSWORD',
    );
    _oldPassword.clear();
    _newPassword.clear();
    _showSnack(context, 'Password change recorded');
  }

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).currentUser;
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    _syncUser(user);
    return TrackPageList(
      children: [
        SectionTitle(
            icon: Icons.person_outline, title: state.t('profileTitle')),
        Text(state.t('profileSub'),
            style: TextStyle(color: colors.muted, fontSize: 12)),
        const SizedBox(height: 10),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: colors.tint(colors.cyan, 34),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colors.cyanBorder),
                      boxShadow: [
                        BoxShadow(
                            color: colors.cyan.withAlpha(34), blurRadius: 18),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        (user?.name.isNotEmpty ?? false)
                            ? user!.name.characters.first.toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: colors.cyan,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? '-',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        if (user != null) _RoleBadge(role: user.role),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _ProfileMetaRow(
                icon: Icons.mail_outline,
                tone: colors.cyan,
                text: user?.email ?? '-',
              ),
              const SizedBox(height: 8),
              _ProfileMetaRow(
                icon: Icons.phone_outlined,
                tone: colors.emerald,
                text: user?.phone ?? '-',
              ),
            ],
          ),
        ),
        SectionCard(
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.tint(colors.cyan, 34),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.cyanBorder),
                ),
                child: Icon(Icons.lock_outline, color: colors.cyan, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Account Access',
                        style: TextStyle(
                          color: colors.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        )),
                    const SizedBox(height: 4),
                    Text(
                      'Credentials control dashboard access, scanner review, and audit actions.',
                      style: TextStyle(color: colors.muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          child: OutlinedButton.icon(
            onPressed: state.logout,
            icon: const Icon(Icons.logout, color: TrackColors.red),
            label: Text(state.t('navLogout')),
          ),
        ),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                  icon: Icons.edit_outlined, title: state.t('editProfileInfo')),
              const SizedBox(height: 10),
              TextField(
                  controller: _name,
                  decoration:
                      InputDecoration(labelText: state.t('fullNameLabel'))),
              const SizedBox(height: 10),
              TextField(
                  controller: _phone,
                  decoration:
                      InputDecoration(labelText: state.t('phoneNumberLabel'))),
              const SizedBox(height: 10),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration:
                    InputDecoration(labelText: state.t('emailAddressLabel')),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: user == null ? null : _saveProfile,
                icon: const Icon(Icons.save_outlined),
                label: Text(state.t('saveProfileBtn')),
              ),
            ],
          ),
        ),
        SectionCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                  icon: Icons.lock_reset, title: state.t('changePassword')),
              const SizedBox(height: 10),
              TextField(
                controller: _oldPassword,
                obscureText: true,
                decoration: InputDecoration(labelText: state.t('oldPassword')),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _newPassword,
                obscureText: true,
                decoration: InputDecoration(labelText: state.t('newPassword')),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: user == null ? null : _changePassword,
                icon: const Icon(Icons.password),
                label: Text(state.t('changePassword')),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key, this.showHeader = false});

  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    final items = <_MoreItem>[
      _MoreItem(
          state.t('navVehicles'), Icons.directions_car, AppSection.vehicles),
      if (state.canManageUsers)
        _MoreItem(
            state.t('navUsers'), Icons.people_alt_outlined, AppSection.users),
      _MoreItem(
          state.t('navSettings'), Icons.settings_outlined, AppSection.settings),
      _MoreItem(
          state.t('navProfile'), Icons.person_outline, AppSection.profile),
    ];

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader) ...[
            SectionTitle(icon: Icons.more_horiz, title: state.t('moreMenu')),
            const SizedBox(height: 8),
          ],
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width < 520 ? 2 : 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 2.4,
            children: [
              for (final item in items)
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => state.go(item.section),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: item.section == state.section
                          ? colors.tint(colors.cyan, 34)
                          : colors.field,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: item.section == state.section
                            ? colors.cyanBorder
                            : colors.border,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(item.icon, color: colors.cyan, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            item.label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoreItem {
  const _MoreItem(this.label, this.icon, this.section);

  final String label;
  final IconData icon;
  final AppSection section;
}

class PermissionPanel extends StatelessWidget {
  const PermissionPanel({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = TrackPalette.of(context);
    return SectionCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: colors.tint(colors.cyan, 34),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.cyanBorder),
            ),
            child: Icon(Icons.lock_outline, color: colors.cyan),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  state.t('readOnlyBadge'),
                  style: TextStyle(
                    color: colors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'This section follows the existing ADMIN / SUPER_ADMIN permission rule.',
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class VehicleDraftDialog extends StatefulWidget {
  const VehicleDraftDialog({super.key, this.vehicle, required this.nextId});

  final Vehicle? vehicle;
  final String nextId;

  @override
  State<VehicleDraftDialog> createState() => _VehicleDraftDialogState();
}

class _VehicleDraftDialogState extends State<VehicleDraftDialog> {
  late final TextEditingController _plate =
      TextEditingController(text: widget.vehicle?.plate ?? '');
  late final TextEditingController _customerName =
      TextEditingController(text: widget.vehicle?.customerName ?? '');
  late final TextEditingController _customerId =
      TextEditingController(text: widget.vehicle?.customerId ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.vehicle?.phone ?? '');
  late final TextEditingController _brand =
      TextEditingController(text: widget.vehicle?.brand ?? '');
  late final TextEditingController _model =
      TextEditingController(text: widget.vehicle?.model ?? '');
  late final TextEditingController _colour =
      TextEditingController(text: widget.vehicle?.colour ?? '');
  late final TextEditingController _year = TextEditingController(
      text: '${widget.vehicle?.year ?? DateTime.now().year}');
  late final TextEditingController _finance =
      TextEditingController(text: widget.vehicle?.financeCompany ?? '');
  late final TextEditingController _amount = TextEditingController(
      text: widget.vehicle?.outstandingAmount.toStringAsFixed(0) ?? '');
  late final TextEditingController _reference =
      TextEditingController(text: widget.vehicle?.reference ?? '');
  late final TextEditingController _remark =
      TextEditingController(text: widget.vehicle?.remark ?? '');
  late VehiclePriority _priority =
      widget.vehicle?.priority ?? VehiclePriority.medium;
  late VehicleStatus _status = widget.vehicle?.status ?? VehicleStatus.active;

  @override
  void dispose() {
    _plate.dispose();
    _customerName.dispose();
    _customerId.dispose();
    _phone.dispose();
    _brand.dispose();
    _model.dispose();
    _colour.dispose();
    _year.dispose();
    _finance.dispose();
    _amount.dispose();
    _reference.dispose();
    _remark.dispose();
    super.dispose();
  }

  void _save() {
    final now = DateTime.now().toUtc();
    final original = widget.vehicle;
    final plate = cleanPlateNumber(_plate.text);
    if (plate.isEmpty || _customerName.text.trim().isEmpty) {
      _showSnack(context, 'Plate and customer name are required');
      return;
    }
    Navigator.of(context).pop(
      Vehicle(
        id: original?.id ?? widget.nextId,
        plate: plate,
        customerName: _customerName.text.trim(),
        customerId: _customerId.text.trim().isEmpty
            ? 'CUST-${widget.nextId}'
            : _customerId.text.trim(),
        phone: _phone.text.trim(),
        brand: _brand.text.trim().isEmpty ? 'Unknown' : _brand.text.trim(),
        model: _model.text.trim().isEmpty ? 'Unknown' : _model.text.trim(),
        colour: _colour.text.trim().isEmpty ? 'Unknown' : _colour.text.trim(),
        year: int.tryParse(_year.text.trim()) ?? DateTime.now().year,
        financeCompany:
            _finance.text.trim().isEmpty ? 'Unassigned' : _finance.text.trim(),
        outstandingAmount: double.tryParse(_amount.text.trim()) ?? 0,
        reference: _reference.text.trim().isEmpty
            ? 'REF-${widget.nextId}'
            : _reference.text.trim(),
        priority: _priority,
        status: _status,
        remark: _remark.text.trim(),
        createdDate: original?.createdDate ?? now,
        updatedDate: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return AlertDialog(
      title:
          Text(widget.vehicle == null ? state.t('addVehicle') : 'Edit Vehicle'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogField(
                  controller: _plate,
                  label: state.t('plateNumber'),
                  textCapitalization: TextCapitalization.characters),
              _DialogField(
                  controller: _customerName, label: state.t('customerName')),
              _DialogField(controller: _customerId, label: 'Customer ID'),
              _DialogField(
                  controller: _phone,
                  label: state.t('phoneNumberLabel'),
                  keyboardType: TextInputType.phone),
              Row(
                children: [
                  Expanded(
                      child: _DialogField(controller: _brand, label: 'Brand')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _DialogField(controller: _model, label: 'Model')),
                ],
              ),
              Row(
                children: [
                  Expanded(
                      child:
                          _DialogField(controller: _colour, label: 'Colour')),
                  const SizedBox(width: 8),
                  Expanded(
                      child: _DialogField(
                          controller: _year,
                          label: 'Year',
                          keyboardType: TextInputType.number)),
                ],
              ),
              _DialogField(
                  controller: _finance, label: state.t('financeCompany')),
              _DialogField(
                  controller: _amount,
                  label: 'Outstanding Amount',
                  keyboardType: TextInputType.number),
              _DialogField(
                  controller: _reference, label: state.t('caseReference')),
              Row(
                children: [
                  Expanded(
                    child: TrackDropdownField<VehiclePriority>(
                      value: _priority,
                      label: state.t('priority'),
                      icon: Icons.priority_high,
                      items: [
                        for (final priority in VehiclePriority.values)
                          DropdownMenuItem(
                              value: priority,
                              child:
                                  Text(_vehiclePriorityLabel(state, priority))),
                      ],
                      onChanged: (value) =>
                          setState(() => _priority = value ?? _priority),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TrackDropdownField<VehicleStatus>(
                      value: _status,
                      label: 'Status',
                      icon: Icons.flag_outlined,
                      items: [
                        for (final status in VehicleStatus.values)
                          DropdownMenuItem(
                              value: status,
                              child: Text(_vehicleStatusLabel(state, status))),
                      ],
                      onChanged: (value) =>
                          setState(() => _status = value ?? _status),
                    ),
                  ),
                ],
              ),
              _DialogField(controller: _remark, label: 'Remark', maxLines: 3),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class UserDraftDialog extends StatefulWidget {
  const UserDraftDialog(
      {super.key, this.user, required this.nextId, this.createdBy});

  final AppUser? user;
  final String nextId;
  final String? createdBy;

  @override
  State<UserDraftDialog> createState() => _UserDraftDialogState();
}

class _UserDraftDialogState extends State<UserDraftDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.user?.name ?? '');
  late final TextEditingController _email =
      TextEditingController(text: widget.user?.email ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.user?.phone ?? '');
  late Role _role = widget.user?.role ?? Role.user;
  late String _status = widget.user?.status ?? 'ACTIVE';

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty || _email.text.trim().isEmpty) {
      _showSnack(context, 'Name and email are required');
      return;
    }
    Navigator.of(context).pop(
      AppUser(
        id: widget.user?.id ?? widget.nextId,
        name: _name.text.trim(),
        email: _email.text.trim(),
        phone: _phone.text.trim(),
        role: _role,
        status: _status,
        avatar: widget.user?.avatar ?? '',
        lastLogin: widget.user?.lastLogin ?? DateTime.now().toUtc(),
        createdBy: widget.user?.createdBy ?? widget.createdBy,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return AlertDialog(
      title: Text(widget.user == null ? state.t('addUser') : 'Edit User'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogField(controller: _name, label: state.t('fullNameLabel')),
              _DialogField(
                  controller: _email,
                  label: state.t('emailAddressLabel'),
                  keyboardType: TextInputType.emailAddress),
              _DialogField(
                  controller: _phone,
                  label: state.t('phoneNumberLabel'),
                  keyboardType: TextInputType.phone),
              Row(
                children: [
                  Expanded(
                    child: TrackDropdownField<Role>(
                      value: _role,
                      label: state.t('roleHeader'),
                      icon: Icons.shield_outlined,
                      items: [
                        for (final role in Role.values)
                          DropdownMenuItem(
                              value: role,
                              child: Text(_roleLabel(state, role))),
                      ],
                      onChanged: (value) =>
                          setState(() => _role = value ?? _role),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TrackDropdownField<String>(
                      value: _status,
                      label: 'Status',
                      icon: Icons.verified_outlined,
                      items: const [
                        DropdownMenuItem(
                            value: 'ACTIVE', child: Text('ACTIVE')),
                        DropdownMenuItem(
                            value: 'DISABLED', child: Text('DISABLED')),
                      ],
                      onChanged: (value) =>
                          setState(() => _status = value ?? _status),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _DialogField extends StatelessWidget {
  const _DialogField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        maxLines: maxLines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}

class VehicleListCard extends StatelessWidget {
  const VehicleListCard({
    super.key,
    required this.vehicle,
    this.canEdit = false,
    this.onEdit,
    this.onDelete,
  });

  final Vehicle vehicle;
  final bool canEdit;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  vehicle.plate,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.cyan,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
              ),
              _StatusBadge(label: vehicle.status.code),
              if (canEdit)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, color: colors.muted),
                  onSelected: (value) {
                    if (value == 'edit') onEdit?.call();
                    if (value == 'delete') onDelete?.call();
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${vehicle.brand} ${vehicle.model} / ${vehicle.colour} / ${vehicle.year}',
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.text,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${vehicle.customerName} / ${vehicle.financeCompany} / ${vehicle.reference}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colors.muted, fontSize: 12),
          ),
          if (vehicle.remark.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              vehicle.remark,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.muted2, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              _PriorityBadge(label: vehicle.priority.code),
              const Spacer(),
              Text(
                _currency(vehicle.outstandingAmount),
                style: TextStyle(
                  color: colors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class UserListCard extends StatelessWidget {
  const UserListCard({
    super.key,
    required this.user,
    required this.canDelete,
    required this.onEdit,
    required this.onToggle,
    required this.onResetPassword,
    required this.onDelete,
    required this.onViewHistory,
  });

  final AppUser user;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onResetPassword;
  final VoidCallback onDelete;
  final VoidCallback onViewHistory;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: colors.tint(colors.cyan, 34),
            foregroundColor: colors.cyan,
            child: Text(
              user.name.isEmpty
                  ? '?'
                  : user.name.characters.first.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        user.name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    _RoleBadge(role: user.role),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  user.email,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  '${user.phone} / ${user.status} / ${_formatTime(user.lastLogin)}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted2, fontSize: 11),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: colors.muted),
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'toggle') onToggle();
              if (value == 'reset') onResetPassword();
              if (value == 'delete') onDelete();
              if (value == 'history') onViewHistory();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(
                  value: 'history', child: Text('View History')),
              PopupMenuItem(
                  value: 'toggle',
                  child: Text(user.status == 'ACTIVE' ? 'Disable' : 'Enable')),
              const PopupMenuItem(
                  value: 'reset', child: Text('Reset Password')),
              if (canDelete)
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    final tone = switch (label) {
      'ACTIVE' => colors.emerald,
      'FLAGGED' => colors.red,
      'PENDING' => colors.amber,
      'CLEARED' => colors.cyan,
      _ => colors.muted,
    };
    final state = AppScope.of(context);
    final displayLabel = switch (label) {
      'ACTIVE' => state.t('statusActive'),
      'FLAGGED' => state.t('statusFlagged'),
      'PENDING' => state.t('statusPending'),
      'CLEARED' => state.t('statusCleared'),
      _ => label,
    };
    return _TinyBadge(label: displayLabel, tone: tone);
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    final tone = switch (label) {
      'HIGH' || 'URGENT' => colors.red,
      'MEDIUM' => colors.amber,
      'LOW' => colors.emerald,
      _ => colors.cyan,
    };
    final state = AppScope.of(context);
    final displayLabel = switch (label) {
      'HIGH' || 'URGENT' => state.t('priorityHigh'),
      'MEDIUM' => state.t('priorityMedium'),
      'LOW' => state.t('priorityLow'),
      _ => label,
    };
    return _TinyBadge(label: displayLabel, tone: tone);
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final Role role;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    final tone = switch (role) {
      Role.superAdmin => colors.cyan,
      Role.admin => colors.blue,
      Role.user => colors.muted,
    };
    return _TinyBadge(label: role.code, tone: tone);
  }
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.label, required this.tone});

  final String label;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: colors.tint(tone, colors.isDark ? 38 : 24),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tone.withAlpha(130)),
      ),
      child: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: tone,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    );
  }
}

class UserHistoryDialog extends StatelessWidget {
  const UserHistoryDialog({super.key, required this.user, required this.logs});

  final AppUser user;
  final List<HistoryLog> logs;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('${user.name} History'),
      content: SizedBox(
        width: 520,
        child: logs.isEmpty
            ? const Text('No audit records for this user yet.')
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final log in logs) _AuditDialogRow(log: log),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _AuditDialogRow extends StatelessWidget {
  const _AuditDialogRow({required this.log});

  final HistoryLog log;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_historyIcon(log.type), color: colors.cyan, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.action,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  log.details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatTime(log.timestamp),
                  style: TextStyle(color: colors.muted2, fontSize: 10),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TinyBadge(
            label: log.statusMatch ?? log.type,
            tone: _historyTone(log.statusMatch ?? log.type),
          ),
        ],
      ),
    );
  }
}

class VehicleMatchCard extends StatelessWidget {
  const VehicleMatchCard(
      {super.key, required this.vehicle, required this.tone});

  final Vehicle vehicle;
  final String tone;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    final resultTone = tone == 'EXACT' ? colors.red : colors.amber;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.field,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: resultTone.withAlpha(150)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              tone == 'EXACT' ? Icons.warning_amber : Icons.help_outline,
              color: resultTone,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vehicle.plate,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.cyan,
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${vehicle.brand} ${vehicle.model} / ${vehicle.customerName}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${vehicle.financeCompany} / ${vehicle.reference}',
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.muted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            _TinyBadge(
              label: tone,
              tone: resultTone,
            ),
          ],
        ),
      ),
    );
  }
}

class HistoryListTile extends StatelessWidget {
  const HistoryListTile({super.key, required this.log});

  final HistoryLog log;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.tint(colors.cyan, 34),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.cyanBorder),
            ),
            child: Icon(_historyIcon(log.type), color: colors.cyan, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  log.plate ?? log.action,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  log.details,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  _formatTime(log.timestamp),
                  style: TextStyle(color: colors.muted2, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TinyBadge(
            label: log.statusMatch ?? log.type,
            tone: _historyTone(log.statusMatch ?? log.type),
          ),
        ],
      ),
    );
  }
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return SectionCard(
      child: Row(
        children: [
          Icon(Icons.inbox_outlined, color: colors.cyan),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: colors.muted,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PagedListControls extends StatelessWidget {
  const PagedListControls({
    super.key,
    required this.totalItems,
    required this.page,
    required this.pageSize,
    required this.onPageChanged,
  });

  final int totalItems;
  final int page;
  final int pageSize;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    final pageCount = ((totalItems + pageSize - 1) ~/ pageSize).clamp(1, 9999);
    final safePage = page.clamp(0, pageCount - 1);
    final start = totalItems == 0 ? 0 : safePage * pageSize + 1;
    final end = (safePage * pageSize + pageSize).clamp(0, totalItems);

    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$start-$end of $totalItems',
              style: TextStyle(color: colors.muted, fontSize: 12),
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'Previous Page',
            onPressed: safePage == 0 ? null : () => onPageChanged(safePage - 1),
            icon: const Icon(Icons.chevron_left),
          ),
          const SizedBox(width: 8),
          Text('${safePage + 1} / $pageCount',
              style:
                  TextStyle(color: colors.text, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Next Page',
            onPressed: safePage >= pageCount - 1
                ? null
                : () => onPageChanged(safePage + 1),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 76),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.cyanBorder),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
              ),
              Icon(icon, color: colors.cyan, size: 16),
            ],
          ),
          Text(
            value,
            style: TextStyle(
              color: colors.text,
              fontSize: 26,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.panel,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.shadow,
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: DefaultTextStyle.merge(
        style: TextStyle(color: colors.text),
        child: child,
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.icon,
    required this.title,
  });

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return Row(
      children: [
        Icon(icon, color: colors.cyan, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title.toUpperCase(),
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.text,
              fontSize: 13,
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}

class MetricChip extends StatelessWidget {
  const MetricChip({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        '$label: $value',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: colors.muted,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class TrackOptionButton extends StatelessWidget {
  const TrackOptionButton({
    super.key,
    required this.selected,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = TrackColors.cyan,
    this.compact = false,
  });

  final bool selected;
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    final effectiveTone = tone == TrackColors.cyan
        ? colors.cyan
        : tone == TrackColors.emerald
            ? colors.emerald
            : tone == TrackColors.amber
                ? colors.amber
                : tone == TrackColors.red
                    ? colors.red
                    : tone == TrackColors.purple
                        ? colors.purple
                        : tone == TrackColors.blue
                            ? colors.blue
                            : tone;
    final disabled = onPressed == null;
    final foreground = disabled
        ? colors.muted2
        : selected
            ? effectiveTone
            : colors.muted;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPressed,
      child: Container(
        constraints: BoxConstraints(minHeight: compact ? 38 : 42),
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: compact ? 8 : 10,
        ),
        decoration: BoxDecoration(
          color: selected
              ? Color.alphaBlend(effectiveTone.withAlpha(38), colors.field)
              : colors.field,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? effectiveTone.withAlpha(150) : colors.border,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: effectiveTone.withAlpha(28),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, color: foreground, size: compact ? 15 : 16),
              const SizedBox(width: 7),
            ],
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: foreground,
                  fontSize: compact ? 11 : 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TrackDropdownField<T> extends StatelessWidget {
  const TrackDropdownField({
    super.key,
    required this.value,
    required this.label,
    required this.items,
    required this.onChanged,
    this.icon,
  });

  final T? value;
  final String label;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    final compact = MediaQuery.sizeOf(context).width < 600;
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      dropdownColor: colors.panelSolid,
      icon: Icon(Icons.keyboard_arrow_down, color: colors.cyan),
      style: TextStyle(
        color: colors.text,
        fontSize: compact ? 11 : 12,
        fontWeight: FontWeight.w800,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: colors.muted,
          fontSize: compact ? 10 : 12,
          fontWeight: FontWeight.w700,
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 12 : 14,
        ),
        prefixIcon: icon == null ? null : Icon(icon, size: compact ? 18 : 20),
        prefixIconConstraints: BoxConstraints(minWidth: compact ? 36 : 48),
      ),
      items: items,
      onChanged: onChanged,
    );
  }
}

class TrackSwitchTile extends StatelessWidget {
  const TrackSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    final enabled = onChanged != null;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value ? colors.cyanBorder : colors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: enabled ? colors.cyan : colors.muted2, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: enabled ? colors.text : colors.muted2,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: colors.cyan,
            activeTrackColor: colors.isDark
                ? const Color(0xFF164E63)
                : const Color(0xFFA5F3FC),
            inactiveThumbColor: colors.muted,
            inactiveTrackColor: colors.isDark
                ? const Color(0xFF1E293B)
                : const Color(0xFFE2E8F0),
          ),
        ],
      ),
    );
  }
}

class TrackEventCard extends StatelessWidget {
  const TrackEventCard({
    super.key,
    required this.track,
    required this.displayPlate,
  });

  final AnprTrack track;
  final String displayPlate;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    final confidence = '${(track.confidence * 100).round()}%';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.tint(colors.cyan, 34),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.cyanBorder),
            ),
            child:
                Icon(Icons.center_focus_strong, color: colors.cyan, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayPlate,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.cyan,
                    fontFamily: 'monospace',
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${track.pipelineState} / ${track.state} / ${track.qualityClass}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.muted, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _TinyBadge(label: confidence, tone: colors.cyan),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(
                color: colors.text,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileMetaRow extends StatelessWidget {
  const _ProfileMetaRow({
    required this.icon,
    required this.tone,
    required this.text,
  });

  final IconData icon;
  final Color tone;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = TrackPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.field,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: tone, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.text,
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Color _trackColor(String matchType) {
  switch (matchType) {
    case 'EXACT':
      return const Color(0xFFEF4444);
    case 'POSSIBLE':
      return const Color(0xFFF59E0B);
    default:
      return const Color(0xFF06B6D4);
  }
}

String _friendlyBridgeError(Object error) {
  if (error is MissingPluginException) {
    return 'Native ANPR plugin is not registered yet. Generate Android/iOS shells and implement the bridge contract.';
  }
  if (error is PlatformException) {
    return error.message ?? error.code;
  }
  return error.toString();
}

String _currency(double value) {
  return 'RM ${value.toStringAsFixed(0)}';
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  final date = local.toString();
  return date.length >= 16 ? date.substring(0, 16) : date;
}

String _roleLabel(AppState state, Role role) {
  switch (role) {
    case Role.user:
      return state.t('roleUser');
    case Role.admin:
      return state.t('roleAdmin');
    case Role.superAdmin:
      return state.t('roleSuperAdmin');
  }
}

String _searchScopeLabel(AppState state, SearchScope scope) {
  switch (scope) {
    case SearchScope.all:
      return 'All';
    case SearchScope.plate:
      return state.t('plateNumber');
    case SearchScope.customer:
      return state.t('customerName');
    case SearchScope.finance:
      return state.t('financeCompany');
    case SearchScope.reference:
      return state.t('caseReference');
    case SearchScope.vehicle:
      return state.t('vehicleDetails');
  }
}

String _vehicleStatusLabel(AppState state, VehicleStatus status) {
  switch (status) {
    case VehicleStatus.active:
      return state.t('statusActive');
    case VehicleStatus.flagged:
      return state.t('statusFlagged');
    case VehicleStatus.pending:
      return state.t('statusPending');
    case VehicleStatus.cleared:
      return state.t('statusCleared');
  }
}

String _vehiclePriorityLabel(AppState state, VehiclePriority priority) {
  switch (priority) {
    case VehiclePriority.high:
      return state.t('priorityHigh');
    case VehiclePriority.medium:
      return state.t('priorityMedium');
    case VehiclePriority.low:
      return state.t('priorityLow');
  }
}

bool _matchesVehicleFilter(
  Vehicle vehicle,
  String query,
  VehicleStatus? status,
  VehiclePriority? priority,
) {
  if (status != null && vehicle.status != status) return false;
  if (priority != null && vehicle.priority != priority) return false;
  final lowerQuery = query.trim().toLowerCase();
  final cleaned = cleanPlateNumber(query);
  if (lowerQuery.isEmpty && cleaned.isEmpty) return true;
  final haystacks = [
    vehicle.plate,
    vehicle.customerName,
    vehicle.customerId,
    vehicle.phone,
    vehicle.brand,
    vehicle.model,
    vehicle.colour,
    vehicle.financeCompany,
    vehicle.reference,
    vehicle.remark,
    vehicle.status.code,
    vehicle.priority.code,
    '${vehicle.year}',
  ];
  return haystacks.any((value) {
    return value.toLowerCase().contains(lowerQuery) ||
        cleanPlateNumber(value).contains(cleaned);
  });
}

bool _matchesHistoryFilter(HistoryLog log, String query, String? type) {
  if (type != null && log.type != type) return false;
  final lowerQuery = query.trim().toLowerCase();
  final cleaned = cleanPlateNumber(query);
  if (lowerQuery.isEmpty && cleaned.isEmpty) return true;
  final haystacks = [
    log.type,
    log.action,
    log.plate ?? '',
    log.details,
    log.statusMatch ?? '',
    log.cameraName ?? '',
    log.actorName ?? '',
    log.userRole.code,
  ];
  return haystacks.any((value) {
    return value.toLowerCase().contains(lowerQuery) ||
        cleanPlateNumber(value).contains(cleaned);
  });
}

bool _matchesUserFilter(
    AppUser user, String query, Role? role, String? status) {
  if (role != null && user.role != role) return false;
  if (status != null && user.status != status) return false;
  final lowerQuery = query.trim().toLowerCase();
  if (lowerQuery.isEmpty) return true;
  return [user.name, user.email, user.phone, user.role.code, user.status]
      .any((value) {
    return value.toLowerCase().contains(lowerQuery);
  });
}

List<T> _pagedItems<T>(List<T> items, int page, int pageSize) {
  if (items.isEmpty) return const [];
  final pageCount = ((items.length + pageSize - 1) ~/ pageSize).clamp(1, 9999);
  final safePage = page.clamp(0, pageCount - 1);
  final start = safePage * pageSize;
  final end = (start + pageSize).clamp(0, items.length);
  return items.sublist(start, end);
}

String _nextVehicleId(List<Vehicle> vehicles) {
  final next = vehicles.length + 1;
  return 'veh-${next.toString().padLeft(3, '0')}';
}

String _nextUserId(List<AppUser> users) {
  final next = users.length + 1;
  return 'user-${next.toString().padLeft(3, '0')}';
}

Map<String, dynamic> _vehicleToAlertMap(Vehicle vehicle) {
  return <String, dynamic>{
    'id': vehicle.id,
    'plate': vehicle.plate,
    'customerName': vehicle.customerName,
    'customerId': vehicle.customerId,
    'phone': vehicle.phone,
    'brand': vehicle.brand,
    'model': vehicle.model,
    'colour': vehicle.colour,
    'year': vehicle.year,
    'financeCompany': vehicle.financeCompany,
    'outstandingAmount': vehicle.outstandingAmount,
    'reference': vehicle.reference,
    'priority': vehicle.priority.code,
    'status': vehicle.status.code,
    'remark': vehicle.remark,
  };
}

String? _alertEvidenceNote(Map<String, dynamic> evidence) {
  final vehicleImagePath = evidence['vehicleImagePath']?.toString() ?? '';
  final plateImagePath = evidence['plateImagePath']?.toString() ?? '';
  final enhancedPlateImagePath =
      evidence['plateEnhancedImagePath']?.toString() ?? '';
  final binaryPlateImagePath =
      evidence['plateBinaryImagePath']?.toString() ?? '';
  final topLineImagePath = evidence['plateTopLineImagePath']?.toString() ?? '';
  final bottomLineImagePath =
      evidence['plateBottomLineImagePath']?.toString() ?? '';
  final innerTextImagePath =
      evidence['plateInnerTextImagePath']?.toString() ?? '';
  final preprocessingVariant =
      evidence['preprocessingVariant']?.toString() ?? '';
  final preprocessingVariants =
      ((evidence['preprocessingVariants'] as List?) ?? const <Object?>[])
          .map((item) => item?.toString() ?? '')
          .where((item) => item.isNotEmpty)
          .join(', ');
  final cropWidth = evidence['plateCropWidth']?.toString() ?? '';
  final cropHeight = evidence['plateCropHeight']?.toString() ?? '';
  if (vehicleImagePath.isEmpty &&
      plateImagePath.isEmpty &&
      enhancedPlateImagePath.isEmpty &&
      binaryPlateImagePath.isEmpty &&
      topLineImagePath.isEmpty &&
      bottomLineImagePath.isEmpty &&
      innerTextImagePath.isEmpty) {
    return null;
  }
  return 'Vehicle image: $vehicleImagePath\n'
      'Plate image: $plateImagePath\n'
      'Enhanced plate image: $enhancedPlateImagePath\n'
      'Binary plate image: $binaryPlateImagePath\n'
      'Top line image: $topLineImagePath\n'
      'Bottom line image: $bottomLineImagePath\n'
      'Inner text image: $innerTextImagePath\n'
      'Preprocessing: $preprocessingVariant $cropWidth x $cropHeight\n'
      'Variants: $preprocessingVariants';
}

String _vehiclesToCsv(List<Vehicle> vehicles) {
  final rows = <List<Object?>>[
    [
      'plate',
      'customer_name',
      'customer_id',
      'phone',
      'brand',
      'model',
      'colour',
      'year',
      'finance_company',
      'outstanding_amount',
      'reference',
      'priority',
      'status',
      'remark',
    ],
    for (final vehicle in vehicles)
      [
        vehicle.plate,
        vehicle.customerName,
        vehicle.customerId,
        vehicle.phone,
        vehicle.brand,
        vehicle.model,
        vehicle.colour,
        vehicle.year,
        vehicle.financeCompany,
        vehicle.outstandingAmount,
        vehicle.reference,
        vehicle.priority.code,
        vehicle.status.code,
        vehicle.remark,
      ],
  ];
  return rows.map(_csvRow).join('\n');
}

String _historyToCsv(List<HistoryLog> history) {
  final rows = <List<Object?>>[
    [
      'timestamp',
      'type',
      'action',
      'plate',
      'details',
      'status',
      'actor',
      'role',
      'camera'
    ],
    for (final log in history)
      [
        log.timestamp.toIso8601String(),
        log.type,
        log.action,
        log.plate ?? '',
        log.details,
        log.statusMatch ?? '',
        log.actorName ?? '',
        log.userRole.code,
        log.cameraName ?? '',
      ],
  ];
  return rows.map(_csvRow).join('\n');
}

String _csvRow(List<Object?> values) {
  return values.map((value) {
    final escaped = '$value'.replaceAll('"', '""');
    return '"$escaped"';
  }).join(',');
}

IconData _historyIcon(String type) {
  switch (type) {
    case 'DETECTION':
      return Icons.camera_alt_outlined;
    case 'DATABASE':
      return Icons.storage_outlined;
    case 'USER':
      return Icons.people_alt_outlined;
    default:
      return Icons.search;
  }
}

Color _historyTone(String value) {
  switch (value) {
    case 'EXACT':
    case 'FLAGGED':
      return TrackColors.red;
    case 'POSSIBLE':
    case 'PENDING':
      return TrackColors.amber;
    case 'NONE':
    case 'CLEARED':
      return TrackColors.emerald;
    case 'DETECTION':
      return TrackColors.blue;
    case 'SEARCH':
      return TrackColors.purple;
    default:
      return TrackColors.cyan;
  }
}

Future<bool> _confirmAction(
    BuildContext context, String title, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Confirm')),
      ],
    ),
  );
  return result ?? false;
}

void _showSnack(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(message)));
}

T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}
