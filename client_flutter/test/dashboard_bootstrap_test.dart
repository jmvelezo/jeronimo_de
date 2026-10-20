import 'package:flutter_test/flutter_test.dart';
import 'package:jeronimo_de/models/app_models.dart';

void main() {
  test('interpreta la carga consolidada del inicio', () {
    final data = DashboardBootstrapData.fromJson({
      'month': '2026-10',
      'active_period': {
        'period_mode': 'calendar',
        'start_day': 1,
        'active_month': '2026-10',
        'period_start': '2026-10-01',
        'period_end': '2026-10-31',
        'label': 'Octubre 2026',
        'is_manual': false,
      },
      'members': [
        {
          'id': 1,
          'household_id': 1,
          'name': 'Solana',
          'color': '#7C3AED',
          'role': 'owner',
          'is_active': true,
        }
      ],
      'participation': [
        {
          'member_id': 1,
          'month': '2026-10',
          'participates': true,
        }
      ],
      'summary': {
        'month': '2026-10',
        'total_income': 0,
        'total_shared_expenses': 0,
        'members': [],
        'settlements': [],
      },
      'advance_payments': [],
      'credit_balances': [],
      'fixed_expenses': [],
      'task_summary': {
        'pending_count': 0,
        'overdue_count': 0,
        'due_soon_count': 0,
        'high_priority_count': 0,
        'assigned_to_me_count': 0,
      },
      'weekly_ai': {
        'report': null,
        'settings': {
          'weekly_enabled': false,
          'analysis_frequency': 'manual',
          'frequency_label': 'Manual',
          'preferred_weekday': 0,
          'preferred_weekday_label': 'Lunes',
          'use_external_context': false,
          'use_news_context': false,
          'currency': 'ARS',
          'country_context': 'Argentina',
        },
        'tips': [],
        'generated_now': false,
        'message': 'Todavía no hay informe.',
      },
    });

    expect(data.month, '2026-10');
    expect(data.activePeriod.activeMonth, data.month);
    expect(data.members.single.name, 'Solana');
    expect(data.weeklyAi.generatedNow, isFalse);
    expect(data.advancePayments, isEmpty);
  });
}
