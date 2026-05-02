import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/friendly_messages.dart';
import '../services/shared_sync_store.dart';
import '../widgets/app_card.dart';
import '../widgets/app_shell.dart';
import 'personal_local_screen.dart';

class AdvancedConfigScreen extends StatefulWidget {
  final ApiService api;
  final SessionData session;
  final VoidCallback onChanged;

  const AdvancedConfigScreen({super.key, required this.api, required this.session, required this.onChanged});

  @override
  State<AdvancedConfigScreen> createState() => _AdvancedConfigScreenState();
}

class _AdvancedConfigScreenState extends State<AdvancedConfigScreen> {
  bool loading = true;
  String? error;
  List<Member> members = [];
  AppCapabilities? capabilities;
  final SharedSyncStore syncStore = SharedSyncStore();
  final serverController = TextEditingController();
  SyncViewState? syncState;
  ServerSyncStatus? serverStatus;
  AiWeeklySettings? aiSettings;
  HouseholdPeriodSettingsItem? periodSettings;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      serverController.text = widget.api.baseUrl;
      final loadedMembers = await widget.api.getMembers(includeInactive: true);
      AppCapabilities? loadedCapabilities;
      ServerSyncStatus? loadedServerStatus;
      AiWeeklySettings? loadedAiSettings;
      HouseholdPeriodSettingsItem? loadedPeriodSettings;
      try {
        loadedCapabilities = await widget.api.getCapabilities();
        loadedServerStatus = await widget.api.getServerSyncStatus();
        loadedAiSettings = await widget.api.getWeeklyAiSettings();
        loadedPeriodSettings = await widget.api.getPeriodSettings();
        await syncStore.markOnline(widget.api.baseUrl);
      } catch (_) {
        loadedCapabilities = null;
        loadedServerStatus = null;
        await syncStore.markOffline();
      }
      final refreshedSyncState = await syncStore.loadSyncViewState(currentServerUrl: widget.api.baseUrl);
      setState(() {
        members = loadedMembers;
        capabilities = loadedCapabilities;
        serverStatus = loadedServerStatus;
        aiSettings = loadedAiSettings;
        periodSettings = loadedPeriodSettings;
        syncState = refreshedSyncState;
      });
    } catch (e) {
      setState(() => error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  bool get isOwner => widget.session.member.role == 'owner';
  bool get isOperator => widget.session.member.role == 'owner' || widget.session.member.role == 'admin';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      appBar: AppBar(title: const Text('Configuración avanzada')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 96),
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Modo de uso', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  _modeTile('Hogar compartido', 'Activo ahora. Los gastos comunes se guardan en el servidor.', true),
                  _modeTile('Personal local', 'Activo. Guarda cuentas, gastos, ingresos, deudas personales y configuración privada en este dispositivo.', true),
                  _modeTile('Híbrido', 'Activo parcialmente: cuentas privadas locales + hogar compartido conectado por servidor.', true),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Espacio personal privado', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Tus cuentas personales quedan guardadas solo en este dispositivo. El hogar compartido sigue usando servidor.'),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: _openPersonalLocal,
                    icon: const Icon(Icons.lock_person_outlined),
                    label: const Text('Abrir modo personal local'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Servidor y sincronización', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: serverController,
                    decoration: const InputDecoration(
                      labelText: 'Ruta del servidor/API',
                      helperText: 'Ej: https://tu-app.railway.app o http://127.0.0.1:8000',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saveServerUrl,
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Guardar ruta'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _testConnection,
                          icon: const Icon(Icons.wifi_tethering_outlined),
                          label: const Text('Probar'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _syncInfoTile(),
                  if (capabilities != null) ...[
                    const SizedBox(height: 8),
                    Text('Versión API: ${capabilities!.version}', style: const TextStyle(color: Colors.black54)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _periodSettingsCard(),
            const SizedBox(height: 12),
            _aiAutomationCard(),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Respaldo del hogar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  const Text('Exporta una copia JSON de los datos comunes. Las cuentas personales locales no salen de este dispositivo.'),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _exportBackup,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('Copiar respaldo JSON'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Integrantes del hogar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                      IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (!isOwner) const Text('Solo el propietario puede agregar, desactivar o cambiar permisos de integrantes.', style: TextStyle(color: Colors.black54)),
                  if (loading) const Padding(padding: EdgeInsets.all(18), child: Center(child: CircularProgressIndicator())),
                  if (error != null) Text(error!, style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                  for (final member in members) _memberTile(member),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: isOwner ? _showAddMemberSheet : null,
                    icon: const Icon(Icons.person_add_alt_1),
                    label: const Text('Agregar integrante'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: JeronimoBottomNav(
        currentIndex: kBottomNavMasIndex,
        onDestinationSelected: _handleBottomNav,
      ),
    );
  }

  void _handleBottomNav(int index) {
    if (index == kBottomNavMasIndex) return;
    if (Navigator.of(context).canPop()) Navigator.of(context).pop(index);
  }

  Future<void> _openPersonalLocal() async {
    final result = await Navigator.of(context).push<int>(
      MaterialPageRoute(builder: (_) => const PersonalLocalScreen(allowSharedNavigation: true)),
    );
    if (!mounted) return;
    if (result is int && Navigator.of(context).canPop()) Navigator.of(context).pop(result);
  }

  Widget _modeTile(String title, String description, bool enabled) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(enabled ? Icons.check_circle : Icons.lock_clock_outlined, color: enabled ? Colors.green : Colors.black38),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(description),
    );
  }



  Widget _periodSettingsCard() {
    final settings = periodSettings;
    final mode = settings?.periodMode ?? 'calendar';
    final startDay = settings?.startDay ?? 1;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Período del hogar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(settings?.label ?? 'Mes calendario por defecto', style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: mode,
            items: const [
              DropdownMenuItem(value: 'calendar', child: Text('Mes calendario')),
              DropdownMenuItem(value: 'custom', child: Text('Corte personalizado')),
            ],
            onChanged: isOperator ? (value) => _updatePeriodSettings(periodMode: value ?? 'calendar', startDay: startDay) : null,
            decoration: const InputDecoration(labelText: 'Tipo de período'),
          ),
          const SizedBox(height: 10),
          if (mode == 'custom')
            DropdownButtonFormField<int>(
              value: startDay < 1 ? 1 : (startDay > 28 ? 28 : startDay),
              items: [for (int day = 1; day <= 28; day++) DropdownMenuItem(value: day, child: Text('Día $day'))],
              onChanged: isOperator ? (value) => _updatePeriodSettings(periodMode: mode, startDay: value ?? 1) : null,
              decoration: const InputDecoration(labelText: 'Día de inicio del período'),
            ),
          if (!isOperator) ...[
            const SizedBox(height: 8),
            const Text('Solo propietario o administrador operativo puede cambiar el período.', style: TextStyle(color: Colors.black54)),
          ],
        ],
      ),
    );
  }

  Future<void> _updatePeriodSettings({required String periodMode, required int startDay}) async {
    try {
      final updated = await widget.api.updatePeriodSettings(periodMode: periodMode, startDay: periodMode == 'calendar' ? 1 : startDay);
      setState(() => periodSettings = updated);
      widget.onChanged();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Período del hogar actualizado.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  Widget _aiAutomationCard() {
    final settings = aiSettings;
    const frequencyItems = [
      DropdownMenuItem(value: 'manual', child: Text('Manual')),
      DropdownMenuItem(value: 'weekly', child: Text('Semanal')),
      DropdownMenuItem(value: 'biweekly', child: Text('Quincenal')),
      DropdownMenuItem(value: 'monthly', child: Text('Mensual')),
    ];
    const weekdayItems = [
      DropdownMenuItem(value: 0, child: Text('Lunes')),
      DropdownMenuItem(value: 1, child: Text('Martes')),
      DropdownMenuItem(value: 2, child: Text('Miércoles')),
      DropdownMenuItem(value: 3, child: Text('Jueves')),
      DropdownMenuItem(value: 4, child: Text('Viernes')),
      DropdownMenuItem(value: 5, child: Text('Sábado')),
      DropdownMenuItem(value: 6, child: Text('Domingo')),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('IA del hogar', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Configura cuándo se genera el análisis del hogar. Los consejos del Inicio salen del último informe guardado, sin llamar a IA cada vez.'),
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings?.weeklyEnabled == true,
            onChanged: (settings?.analysisFrequency == 'manual') ? null : (value) => _updateAiSettings(weeklyEnabled: value),
            title: const Text('Análisis automático', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(settings?.analysisFrequency == 'manual' ? 'Modo manual: solo se genera desde la pestaña IA.' : 'Activa o pausa la generación automática.'),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: settings?.analysisFrequency ?? 'weekly',
            items: frequencyItems,
            onChanged: (value) => _updateAiSettings(analysisFrequency: value ?? 'weekly'),
            decoration: const InputDecoration(labelText: 'Frecuencia del análisis'),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<int>(
            value: settings?.preferredWeekday ?? 0,
            items: weekdayItems,
            onChanged: (value) => _updateAiSettings(preferredWeekday: value ?? 0),
            decoration: const InputDecoration(labelText: 'Día de ejecución'),
          ),
          const SizedBox(height: 10),
          if (settings != null) ...[
            _infoLine(Icons.schedule_outlined, 'Último análisis', settings.lastReportCreatedAt?.replaceFirst('T', ' ').split('.').first ?? 'Todavía no hay informe generado'),
            const SizedBox(height: 6),
            _infoLine(Icons.event_available_outlined, 'Próximo análisis', settings.nextAnalysisHint ?? 'Sin estimación disponible'),
            const SizedBox(height: 6),
            Text('Base: ${settings.currency} · Contexto: ${settings.countryContext} · Día: ${settings.preferredWeekdayLabel}', style: const TextStyle(color: Colors.black54, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );
  }

  Widget _infoLine(IconData icon, String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: Colors.black54),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.black87, height: 1.25),
              children: [
                TextSpan(text: '$title: ', style: const TextStyle(fontWeight: FontWeight.w900)),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _updateAiSettings({bool? weeklyEnabled, String? analysisFrequency, int? preferredWeekday}) async {
    try {
      final updated = await widget.api.updateWeeklyAiSettings(
        weeklyEnabled: weeklyEnabled,
        analysisFrequency: analysisFrequency,
        preferredWeekday: preferredWeekday,
      );
      setState(() => aiSettings = updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Configuración IA actualizada.')));
      }
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
      }
    }
  }

  Widget _syncInfoTile() {
    final state = syncState;
    final status = serverStatus;
    final online = status?.ok == true || state?.online == true;
    final color = online ? Colors.green : Colors.orange;
    final last = state?.lastSuccessfulSync == null
        ? 'Sin sincronización registrada'
        : 'Última sincronización: ${state!.lastSuccessfulSync!.toLocal().toString().substring(0, 16)}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Icon(online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(online ? 'Servidor disponible' : 'Servidor sin confirmar', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
                Text(status?.message ?? state?.message ?? 'Usá Probar para validar la ruta.', style: const TextStyle(color: Colors.black54)),
                Text(last, style: const TextStyle(color: Colors.black45, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveServerUrl() async {
    final next = serverController.text.trim();
    if (next.isEmpty) return;
    widget.api.baseUrl = next.endsWith('/') ? next.substring(0, next.length - 1) : next;
    await widget.api.saveConfig();
    await syncStore.saveServerUrl(widget.api.baseUrl);
    widget.onChanged();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ruta del servidor guardada.')));
    }
    await _testConnection();
  }

  Future<void> _testConnection() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      widget.api.baseUrl = serverController.text.trim().isEmpty ? widget.api.baseUrl : serverController.text.trim();
      final status = await widget.api.getServerSyncStatus();
      await syncStore.markOnline(widget.api.baseUrl);
      final state = await syncStore.loadSyncViewState(currentServerUrl: widget.api.baseUrl);
      setState(() {
        serverStatus = status;
        syncState = state;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Servidor conectado correctamente.')));
      }
    } catch (e) {
      await syncStore.markOffline();
      final state = await syncStore.loadSyncViewState(currentServerUrl: widget.api.baseUrl);
      setState(() {
        serverStatus = null;
        syncState = state;
        error = friendlyMessage(e);
      });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _exportBackup() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final backup = await widget.api.exportHouseholdBackup();
      final text = const JsonEncoder.withIndent('  ').convert(backup);
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Respaldo JSON copiado al portapapeles.')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = friendlyMessage(e));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'owner':
        return 'Propietario';
      case 'admin':
        return 'Administrador operativo';
      default:
        return 'Integrante';
    }
  }

  Widget _memberTile(Member member) {
    final status = member.isActive ? 'Activo' : 'Inactivo';
    final canChangeRole = isOwner && member.role != 'owner';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(backgroundColor: _parseColor(member.color), child: Text(member.name.substring(0, 1).toUpperCase())),
      title: Text(member.name),
      subtitle: Text('${_roleLabel(member.role)} · $status'),
      trailing: isOwner
          ? Wrap(
              spacing: 4,
              children: [
                if (canChangeRole)
                  IconButton(
                    tooltip: member.role == 'admin' ? 'Quitar admin operativo' : 'Hacer admin operativo',
                    icon: Icon(member.role == 'admin' ? Icons.admin_panel_settings : Icons.add_moderator_outlined),
                    onPressed: () => _setRole(member, member.role == 'admin' ? 'member' : 'admin'),
                  ),
                Switch(value: member.isActive, onChanged: member.role == 'owner' ? null : (value) => _setActive(member, value)),
              ],
            )
          : null,
    );
  }


  Future<void> _setRole(Member member, String role) async {
    try {
      await widget.api.updateMember(memberId: member.id, role: role);
      await _load();
      widget.onChanged();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  Future<void> _setActive(Member member, bool value) async {
    try {
      await widget.api.setMemberActive(memberId: member.id, isActive: value);
      await _load();
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
      }
    }
  }

  Future<void> _showAddMemberSheet() async {
    final nameController = TextEditingController();
    final pinController = TextEditingController();
    String role = 'member';
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(left: 18, right: 18, top: 18, bottom: MediaQuery.of(context).viewInsets.bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Nuevo integrante', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              TextField(controller: nameController, decoration: const InputDecoration(labelText: 'Nombre')),
              const SizedBox(height: 10),
              TextField(controller: pinController, obscureText: true, decoration: const InputDecoration(labelText: 'PIN')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: role,
                items: const [
                  DropdownMenuItem(value: 'member', child: Text('Integrante')),
                  DropdownMenuItem(value: 'admin', child: Text('Administrador operativo')),
                ],
                onChanged: (value) => setModalState(() => role = value ?? 'member'),
                decoration: const InputDecoration(labelText: 'Rol'),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await widget.api.createMember(name: nameController.text.trim(), pin: pinController.text.trim(), role: role);
                    if (mounted) Navigator.pop(context);
                    await _load();
                    widget.onChanged();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
                    }
                  }
                },
                child: const Text('Guardar integrante'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _parseColor(String value) {
    final clean = value.replaceAll('#', '');
    final parsed = int.tryParse('FF$clean', radix: 16);
    return Color(parsed ?? 0xFF7C3AED);
  }
}
