import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/friendly_messages.dart';
import '../widgets/app_card.dart';
import '../widgets/app_shell.dart';
import 'dashboard_screen.dart';
import 'personal_local_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late ApiService api;
  bool loading = true;
  bool creating = false;
  bool advancedOpen = false;
  String? error;
  LastHomeSession? lastHome;

  final serverController = TextEditingController();
  final codeController = TextEditingController();
  final nameController = TextEditingController();
  final pinController = TextEditingController();
  final lastPinController = TextEditingController();

  final houseNameController = TextEditingController(text: 'Casa');
  final firstNameController = TextEditingController(text: 'José');
  final firstPinController = TextEditingController();
  final secondNameController = TextEditingController(text: 'Integrante 2');
  final secondPinController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadApi();
  }

  Future<void> _loadApi() async {
    api = await ApiService.load();
    final savedHome = await ApiService.loadLastHomeSession();
    serverController.text = savedHome?.serverUrl ?? api.baseUrl;
    if (savedHome != null) {
      codeController.text = savedHome.inviteCode;
      nameController.text = savedHome.memberName;
    }
    setState(() {
      lastHome = savedHome;
      loading = false;
    });
  }

  Future<void> _loginLastHome() async {
    final saved = lastHome;
    if (saved == null) return;
    setState(() {
      error = null;
      loading = true;
    });
    try {
      if (lastPinController.text.trim().isEmpty) {
        throw Exception('Poné tu PIN para entrar al último hogar.');
      }
      api.baseUrl = saved.serverUrl;
      serverController.text = saved.serverUrl;
      final session = await api.login(
        householdCode: saved.inviteCode,
        memberName: saved.memberName,
        pin: lastPinController.text.trim(),
      );
      _openDashboard(session);
    } catch (e) {
      setState(() => error = _friendly(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _copyLastHomeCode() async {
    final saved = lastHome;
    if (saved == null) return;
    await Clipboard.setData(ClipboardData(text: saved.inviteCode));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código de hogar copiado.')));
    }
  }

  Future<bool> _confirmDuplicateHomeNameIfNeeded() async {
    final saved = lastHome;
    if (saved == null) return true;
    final newName = houseNameController.text.trim().toLowerCase();
    if (newName.isEmpty || newName != saved.householdName.trim().toLowerCase()) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ya tenés un hogar con ese nombre'),
        content: Text('El último hogar guardado también se llama "${saved.householdName}". Su código es ${saved.inviteCode}. ¿Querés crear otro hogar de todos modos?'),
        actions: [
          TextButton(
            onPressed: () {
              codeController.text = saved.inviteCode;
              nameController.text = saved.memberName;
              Navigator.pop(context, false);
            },
            child: const Text('Usar el existente'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Crear otro')),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _showCreatedHouseholdDialog(SessionData session) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Hogar creado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nombre: ${session.household.name}'),
            const SizedBox(height: 12),
            const Text('Código de hogar', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            SelectableText(
              session.household.inviteCode,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1.2, color: kPrimary),
            ),
            const SizedBox(height: 10),
            const Text('Guardalo o compartilo: sirve para que otra persona entre al hogar con su nombre y PIN.', style: TextStyle(color: kMuted, height: 1.3)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: session.household.inviteCode));
              if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Código copiado.')));
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar código'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entrar')),
        ],
      ),
    );
  }

  Future<void> _login() async {
    setState(() {
      error = null;
      loading = true;
    });
    try {
      if (codeController.text.trim().isEmpty || nameController.text.trim().isEmpty || pinController.text.trim().isEmpty) {
        throw Exception('Completá código del hogar, tu nombre y tu PIN.');
      }
      api.baseUrl = serverController.text.trim().isEmpty ? api.baseUrl : serverController.text.trim();
      final session = await api.login(
        householdCode: codeController.text.trim(),
        memberName: nameController.text.trim(),
        pin: pinController.text.trim(),
      );
      _openDashboard(session);
    } catch (e) {
      setState(() => error = _friendly(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _register() async {
    setState(() {
      error = null;
      loading = true;
    });
    try {
      final secondName = secondNameController.text.trim();
      final secondPin = secondPinController.text.trim();
      if (houseNameController.text.trim().isEmpty || firstNameController.text.trim().isEmpty || firstPinController.text.trim().isEmpty) {
        throw Exception('Completá nombre del hogar, tu nombre y tu PIN.');
      }
      if ((secondName.isEmpty && secondPin.isNotEmpty) || (secondName.isNotEmpty && secondPin.isEmpty)) {
        throw Exception('Para agregar a otra persona, completá nombre y PIN. También podés dejar ambos vacíos y sumarla después.');
      }
      final confirmed = await _confirmDuplicateHomeNameIfNeeded();
      if (!confirmed) {
        setState(() => loading = false);
        return;
      }
      api.baseUrl = serverController.text.trim().isEmpty ? api.baseUrl : serverController.text.trim();
      final session = await api.registerHousehold(
        householdName: houseNameController.text.trim(),
        joseName: firstNameController.text.trim(),
        josePin: firstPinController.text.trim(),
        otherName: secondNameController.text.trim(),
        otherPin: secondPinController.text.trim(),
      );
      await _showCreatedHouseholdDialog(session);
      if (mounted) _openDashboard(session);
    } catch (e) {
      setState(() => error = _friendly(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _friendly(Object error) {
    final raw = friendlyMessage(error);
    if (raw.toLowerCase().contains('incorrecto')) return 'No encontramos ese hogar o el PIN no coincide.';
    if (raw.toLowerCase().contains('server')) return 'No pudimos conectar con el hogar. Revisá la conexión o la configuración avanzada.';
    return raw;
  }

  void _openDashboard(SessionData session) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => DashboardScreen(api: api, session: session)),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading && serverController.text.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: AppGradientBackground(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _loginBrandHeader(),
                  const SizedBox(height: 14),
                  AppCard(
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        SectionTitle(
                          title: 'Elegí cómo empezar',
                          subtitle: 'Lo técnico está guardado en Configuración avanzada.',
                          icon: Icons.explore_outlined,
                        ),
                        Text('• Mis cuentas: uso privado en este dispositivo.', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)),
                        SizedBox(height: 6),
                        Text('• Entrar a hogar: usá código, nombre y PIN.', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)),
                        SizedBox(height: 6),
                        Text('• Crear hogar: podés sumar o desactivar integrantes después.', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.black54)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (error != null) ...[
                    FriendlyError(message: error!),
                    const SizedBox(height: 14),
                  ],
                  if (lastHome != null) ...[
                    _lastHomeCard(),
                    const SizedBox(height: 14),
                  ],
                  _personalModeCard(),
                  const SizedBox(height: 14),
                  _sharedHomeCard(),
                  const SizedBox(height: 14),
                  _createHomeCard(),
                  const SizedBox(height: 14),
                  _advancedCard(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _loginBrandHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = (constraints.maxWidth / 3.2).clamp(128.0, 184.0).toDouble();
        return AppCard(
          padding: EdgeInsets.zero,
          color: Colors.white.withOpacity(0.96),
          border: Border.all(color: kPrimarySoft.withOpacity(0.34)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: SizedBox(
              width: double.infinity,
              height: height,
              child: Transform.scale(
                scale: 1.045,
                child: Image.asset(
                  kBrandLoginHeader,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  filterQuality: FilterQuality.high,
                  isAntiAlias: true,
                  errorBuilder: (context, error, stackTrace) => Container(
                  padding: const EdgeInsets.all(18),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF7C3AED), Color(0xFF5B21B6), Color(0xFF3B0764)],
                    ),
                  ),
                  child: Row(
                    children: [
                      BrandAssetIcon(
                        assetPath: kBrandNavCasa,
                        fallbackIcon: Icons.home_rounded,
                        size: 46,
                        frameSize: 58,
                        borderRadius: 22,
                        padding: 4,
                        backgroundColor: Colors.white.withOpacity(0.94),
                        borderColor: Colors.white.withOpacity(0.24),
                        fallbackColor: kPrimary,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('ECONOMÍA DOMÉSTICA SIMPLE', style: TextStyle(color: Colors.white.withOpacity(0.72), fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 0.8)),
                            const SizedBox(height: 4),
                            const Text('Jeronimo Dé', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                            const SizedBox(height: 5),
                            Text('Tus cuentas personales y los gastos de casa, sin planillas imposibles.', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white.withOpacity(0.86), height: 1.25, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _lastHomeCard() {
    final saved = lastHome!;
    return AppCard(
      gradient: const LinearGradient(colors: [Color(0xFF7C3AED), Color(0xFF4C1D95)]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.16), borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.history_rounded, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Último hogar', style: TextStyle(color: Colors.white.withOpacity(0.78), fontWeight: FontWeight.w800)),
                    Text(saved.householdName, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900)),
                    Text('Código ${saved.inviteCode} · ${saved.memberName}', style: TextStyle(color: Colors.white.withOpacity(0.82), fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Copiar código',
                onPressed: _copyLastHomeCode,
                icon: const Icon(Icons.copy, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: lastPinController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'PIN de ${saved.memberName}',
              fillColor: Colors.white.withOpacity(0.94),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: loading ? null : _loginLastHome,
            icon: const Icon(Icons.login_rounded),
            label: Text(loading ? 'Entrando...' : 'Entrar al último hogar'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: kPrimary),
          ),
        ],
      ),
    );
  }

  Widget _personalModeCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            title: 'Usar solo mis cuentas',
            subtitle: 'Modo privado en este dispositivo. No requiere servidor.',
            icon: Icons.lock_person_outlined,
          ),
          BigActionButton(
            onPressed: loading ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PersonalLocalScreen())),
            icon: Icons.person_outline,
            title: 'Entrar a mis finanzas',
            subtitle: 'Gastos, cuentas y deudas personales',
          ),
        ],
      ),
    );
  }

  Widget _sharedHomeCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(
            title: 'Entrar a un hogar',
            subtitle: 'Para gastos comunes, reparto proporcional y deudas compartidas.',
            icon: Icons.groups_2_outlined,
          ),
          TextField(controller: codeController, decoration: const InputDecoration(labelText: 'Código del hogar')),
          const SizedBox(height: 12),
          TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Tu nombre')),
          const SizedBox(height: 12),
          TextField(controller: pinController, obscureText: true, decoration: const InputDecoration(labelText: 'PIN')),
          const SizedBox(height: 16),
          BigActionButton(
            onPressed: loading ? null : _login,
            icon: Icons.login_rounded,
            title: loading ? 'Entrando...' : 'Entrar al hogar',
          ),
        ],
      ),
    );
  }

  Widget _createHomeCard() {
    return AppCard(
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: creating,
          onExpansionChanged: (value) => setState(() => creating = value),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          leading: const Icon(Icons.add_home_work_outlined, color: kPrimary),
          title: const Text('Crear hogar nuevo', style: TextStyle(fontWeight: FontWeight.w900)),
          subtitle: const Text('Al crearlo, la app te va a mostrar el código para guardar o compartir.'),
          children: [
            const SizedBox(height: 12),
            TextField(controller: houseNameController, decoration: const InputDecoration(labelText: 'Nombre del hogar')),
            const SizedBox(height: 12),
            TextField(controller: firstNameController, decoration: const InputDecoration(labelText: 'Tu nombre')),
            const SizedBox(height: 12),
            TextField(controller: firstPinController, obscureText: true, decoration: const InputDecoration(labelText: 'Tu PIN')),
            const SizedBox(height: 12),
            TextField(controller: secondNameController, decoration: const InputDecoration(labelText: 'Otra persona')),
            const SizedBox(height: 12),
            TextField(controller: secondPinController, obscureText: true, decoration: const InputDecoration(labelText: 'PIN de la otra persona')),
            const SizedBox(height: 16),
            BigActionButton(
              onPressed: loading ? null : _register,
              icon: Icons.check_circle_outline,
              title: loading ? 'Creando...' : 'Crear y entrar',
            ),
          ],
        ),
      ),
    );
  }

  Widget _advancedCard() {
    return AppCard(
      color: Colors.white.withOpacity(0.82),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: advancedOpen,
          onExpansionChanged: (value) => setState(() => advancedOpen = value),
          tilePadding: EdgeInsets.zero,
          childrenPadding: EdgeInsets.zero,
          leading: const Icon(Icons.tune_outlined, color: Colors.black54),
          title: const Text('Configuración avanzada', style: TextStyle(fontWeight: FontWeight.w900)),
          subtitle: const Text('Servidor, pruebas locales y conexión técnica.'),
          children: [
            const SizedBox(height: 12),
            TextField(controller: serverController, decoration: const InputDecoration(labelText: 'Ruta del servidor')),
            const SizedBox(height: 8),
            const Text('Uso normal: no hace falta tocar esto. Para pruebas locales suele ser http://127.0.0.1:8000', style: TextStyle(color: Colors.black54, height: 1.25)),
          ],
        ),
      ),
    );
  }
}
