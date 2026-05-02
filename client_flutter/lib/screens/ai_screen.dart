import 'package:flutter/material.dart';
import '../models/app_models.dart';
import '../services/api_service.dart';
import '../services/friendly_messages.dart';
import '../widgets/app_card.dart';
import '../widgets/app_shell.dart';

class AiScreen extends StatefulWidget {
  final ApiService api;
  final String month;
  final Member currentMember;
  final bool embedded;

  const AiScreen({super.key, required this.api, required this.month, required this.currentMember, this.embedded = false});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  bool loading = true;
  bool generating = false;
  bool weeklyGenerating = false;
  String? error;
  List<AiReportItem> reports = [];
  AiWeeklySettings? weeklySettings;
  AiWeeklyReportResult? weeklyResult;

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
      final loaded = await widget.api.getHouseholdAiReports(widget.month);
      AiWeeklySettings? settings;
      AiWeeklyReportResult? latest;
      try {
        settings = await widget.api.getWeeklyAiSettings();
        latest = await widget.api.getLatestWeeklyAiReport();
      } catch (_) {}
      setState(() {
        reports = loaded;
        weeklySettings = settings;
        weeklyResult = latest;
      });
    } catch (e) {
      setState(() => error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _generate() async {
    setState(() {
      generating = true;
      error = null;
    });
    try {
      await widget.api.createHouseholdAiReport(month: widget.month, focus: 'ahorro, consumo, deudas y tareas');
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe IA del hogar generado y compartido.')));
      }
    } catch (e) {
      setState(() => error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => generating = false);
    }
  }

  Future<void> _generateWeekly() async {
    setState(() {
      weeklyGenerating = true;
      error = null;
    });
    try {
      final result = await widget.api.createWeeklyAiReport(month: widget.month, force: true);
      await _load();
      setState(() => weeklyResult = result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Análisis IA actualizado.')));
      }
    } catch (e) {
      setState(() => error = friendlyMessage(e));
    } finally {
      if (mounted) setState(() => weeklyGenerating = false);
    }
  }

  Future<void> _toggleWeekly(bool enabled) async {
    try {
      final updated = await widget.api.updateWeeklyAiSettings(weeklyEnabled: enabled);
      setState(() => weeklySettings = updated);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(enabled ? 'Análisis automático activado.' : 'Análisis automático desactivado.')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  Future<void> _toggleExternal(bool value) async {
    try {
      final updated = await widget.api.updateWeeklyAiSettings(useExternalContext: value);
      setState(() => weeklySettings = updated);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  Future<void> _toggleNews(bool value) async {
    try {
      final updated = await widget.api.updateWeeklyAiSettings(useNewsContext: value);
      setState(() => weeklySettings = updated);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = _content();
    if (widget.embedded) return content;
    return Scaffold(
      extendBody: true,
      appBar: AppBar(title: const Text('IA del hogar')),
      body: AppGradientBackground(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 90),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(children: [content]),
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

  Widget _content() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle(
          title: 'IA del hogar',
          subtitle: 'Informe compartido, análisis configurable, consejos visibles y trazabilidad.',
          icon: Icons.psychology_alt_outlined,
        ),
        _weeklyControlCard(),
        const SizedBox(height: 14),
        AppCard(
          gradient: const LinearGradient(colors: [Color(0xFF312E81), Color(0xFF7C3AED)]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_awesome, color: Colors.white),
                  SizedBox(width: 10),
                  Expanded(child: Text('Analizar el mes común', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900))),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'La IA toma gastos comunes, deudas, reparto y tareas del hogar. No usa tus finanzas personales locales.',
                style: TextStyle(color: Colors.white.withOpacity(0.86), height: 1.3),
              ),
              const SizedBox(height: 14),
              ElevatedButton.icon(
                onPressed: generating ? null : _generate,
                icon: generating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.insights),
                label: Text(generating ? 'Generando...' : 'Generar informe mensual compartido'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (error != null) ...[
          FriendlyError(message: error!),
          const SizedBox(height: 14),
        ],
        if (loading) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (!loading && reports.isEmpty)
          const EmptyState(
            icon: Icons.auto_awesome_outlined,
            title: 'Sin informes todavía',
            message: 'Generá el primer informe IA del hogar para dejar recomendaciones compartidas y trazables.',
          ),
        for (final report in reports) ...[
          _ReportCard(report: report),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _weeklyControlCard() {
    final settings = weeklySettings;
    final tips = weeklyResult?.tips ?? [];
    return AppCard(
      color: const Color(0xFFF5F3FF),
      border: Border.all(color: const Color(0xFFC4B5FD)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calendar_month_outlined, color: kPrimary),
              const SizedBox(width: 10),
              const Expanded(child: Text('Análisis automático con contexto económico', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              Switch(value: settings?.weeklyEnabled == true, onChanged: _toggleWeekly),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Opera en ARS. Puede mirar dólar e indicadores/noticias como contexto, pero los gastos y deudas del hogar siguen calculándose en pesos.',
            style: TextStyle(color: Colors.black54, height: 1.32, fontWeight: FontWeight.w600),
          ),
          if (settings != null) ...[
            const SizedBox(height: 8),
            Text('Frecuencia: ${settings.frequencyLabel} · Día: ${settings.preferredWeekdayLabel}', style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w800)),
            if (settings.nextAnalysisHint != null)
              Text(settings.nextAnalysisHint!, style: const TextStyle(color: Colors.black45, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 10),
          if (settings != null) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.useExternalContext,
              onChanged: _toggleExternal,
              title: const Text('Usar indicadores económicos externos', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Dólar como indicador contextual y otras señales disponibles.'),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: settings.useNewsContext,
              onChanged: _toggleNews,
              title: const Text('Usar noticias como contexto', style: TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('Solo como contexto narrativo, no como dato único.'),
            ),
          ],
          if (tips.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('Consejos visibles esta semana', style: TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            for (final tip in tips.take(3))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tips_and_updates_outlined, color: kPrimary),
                title: Text(tip.title, style: const TextStyle(fontWeight: FontWeight.w900)),
                subtitle: Text(tip.body),
              ),
          ],
          const SizedBox(height: 12),
          BigActionButton(
            onPressed: weeklyGenerating ? null : _generateWeekly,
            icon: Icons.auto_awesome,
            title: weeklyGenerating ? 'Analizando...' : 'Generar análisis ahora',
            subtitle: 'Crea informe completo y consejos para el Inicio',
          ),
        ],
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final AiReportItem report;

  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context) {
    final dateLabel = report.createdAt.isEmpty ? report.month : report.createdAt.replaceFirst('T', ' ').split('.').first;
    final analysisType = report.evidence['analysis_type']?.toString() ?? 'monthly_manual';
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: kPrimary.withOpacity(0.10), borderRadius: BorderRadius.circular(16)),
                child: Icon(analysisType == 'weekly_contextual' ? Icons.calendar_month_outlined : Icons.auto_awesome, color: kPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(report.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text('$dateLabel · ${report.modelLabel}', style: const TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(report.content, style: const TextStyle(height: 1.36)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(label: Text(report.generatedWithApi ? 'API IA' : 'Consejo local del servidor')),
              Chip(label: Text(analysisType == 'weekly_contextual' ? 'Contextual' : 'Mensual')),
              const Chip(label: Text('ARS base')),
              const Chip(label: Text('Trazable')),
            ],
          ),
        ],
      ),
    );
  }
}
