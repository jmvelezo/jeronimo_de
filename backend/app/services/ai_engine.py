import json
import urllib.request
from datetime import date, timedelta
from typing import Any


def _money(value: float) -> str:
    return f"$ {value:,.0f}".replace(",", ".")


def _safe_text(value: Any) -> str:
    return str(value or "").strip()


def _as_float(value: Any) -> float:
    try:
        return float(value or 0)
    except Exception:
        return 0.0


def _top_items(items: list[dict[str, Any]], key: str = "amount", limit: int = 3) -> list[dict[str, Any]]:
    return sorted([item for item in items if isinstance(item, dict)], key=lambda item: abs(_as_float(item.get(key))), reverse=True)[:limit]


def _line_items(items: list[dict[str, Any]], label_key: str, amount_key: str, limit: int = 3) -> str:
    selected = _top_items(items, amount_key, limit)
    if not selected:
        return "sin datos suficientes"
    return "; ".join(f"{_safe_text(item.get(label_key)) or 'sin categoría'}: {_money(_as_float(item.get(amount_key)))}" for item in selected)


def _fallback_tip(title: str, body: str, level: str = "info", kind: str = "general") -> dict[str, Any]:
    return {
        "title": title,
        "body": body,
        "level": level,
        "kind": kind,
        "valid_until": (date.today() + timedelta(days=7)).isoformat(),
    }


def _heuristic_household_report(data: dict[str, Any]) -> tuple[str, str]:
    summary = data.get("summary", {})
    expenses_by_category = data.get("expenses_by_category", [])
    category_variations = data.get("category_variations", [])
    anomalies = data.get("expense_anomalies", [])
    active_debts = data.get("active_debts", [])
    credit_balances = data.get("credit_balances", [])
    advance_payments = data.get("monthly_advance_payments", [])
    fixed_summary = data.get("fixed_expense_summary", {})
    comparison = data.get("month_comparison", {})
    task_summary = data.get("task_summary", {})
    month = data.get("month", "mes actual")
    previous_month = data.get("previous_month", "mes anterior")

    total_income = _as_float(summary.get("total_income"))
    total_expenses = _as_float(summary.get("total_shared_expenses"))
    previous_expenses = _as_float(comparison.get("previous_total_shared_expenses"))
    expense_delta = _as_float(comparison.get("expense_delta"))
    ratio = (total_expenses / total_income * 100) if total_income else 0
    biggest = expenses_by_category[0] if expenses_by_category else None
    debt_total = sum(_as_float(item.get("remaining_amount")) for item in active_debts)
    credit_total = sum(_as_float(item.get("remaining_amount")) for item in credit_balances)
    pending_advance_total = sum(_as_float(item.get("amount")) for item in advance_payments if str(item.get("status")) == "pending")
    overdue_tasks = int(task_summary.get("overdue_count") or 0)
    due_soon = int(task_summary.get("due_soon_count") or 0)
    fixed_expected = _as_float(fixed_summary.get("active_total_expected"))
    fixed_count = int(fixed_summary.get("active_count") or 0)

    lines = [
        f"Análisis del hogar para {month}",
        "",
        "Diagnóstico breve:",
        f"- Gastos comunes registrados: {_money(total_expenses)} sobre ingresos declarados por {_money(total_income)}.",
    ]
    if total_income > 0:
        lines.append(f"- Peso del gasto común sobre ingresos cargados: {ratio:.1f}%.")
    else:
        lines.append("- Faltan ingresos cargados: sin eso la lectura proporcional del mes queda incompleta.")

    if previous_expenses > 0:
        sign = "subió" if expense_delta > 0 else "bajó" if expense_delta < 0 else "se mantuvo"
        lines.append(f"- Frente a {previous_month}, el gasto común {sign} {_money(abs(expense_delta))}.")
    else:
        lines.append(f"- No hay histórico suficiente en {previous_month} para comparar con precisión.")

    if biggest:
        lines.append(f"- Mayor categoría del período: {_safe_text(biggest.get('category'))}, con {_money(_as_float(biggest.get('amount')))}.")

    lines.extend(["", "Cambios y alertas:"])
    rising = [item for item in category_variations if item.get("status") in {"up", "new"} and _as_float(item.get("delta_amount")) > 0]
    if rising:
        for item in rising[:3]:
            pct = item.get("variation_pct")
            pct_text = f" ({pct:.0f}%)" if isinstance(pct, (int, float)) else ""
            lines.append(f"- {item.get('category')}: +{_money(_as_float(item.get('delta_amount')))}{pct_text} frente al período anterior.")
    else:
        lines.append("- No aparecen aumentos fuertes por categoría con el histórico disponible.")

    if anomalies:
        lines.append("- Gastos inusuales detectados: " + "; ".join(f"{item.get('category')} {_money(_as_float(item.get('amount')))}" for item in anomalies[:3]) + ".")
    if fixed_count:
        lines.append(f"- Hay {fixed_count} gasto(s) fijo(s) activo(s), por un estimado mensual de {_money(fixed_expected)}. Conviene verificar si ya fueron generados este período.")

    lines.extend(["", "Deudas, saldos y pagos:"])
    if debt_total > 0:
        lines.append(f"- Deudas activas/parciales: {_money(debt_total)}. Priorizar las más antiguas o las que generan confusión entre integrantes.")
    else:
        lines.append("- No aparecen deudas activas o parciales relevantes.")
    if credit_total > 0:
        lines.append(f"- Saldos a favor disponibles: {_money(credit_total)}. No mezclarlos con el saldo provisorio; aplicarlos solo contra deudas compatibles.")
    if pending_advance_total > 0:
        lines.append(f"- Pagos anticipados pendientes de confirmación: {_money(pending_advance_total)}.")

    lines.extend(["", "Tareas y riesgos domésticos:"])
    if overdue_tasks or due_soon:
        lines.append(f"- Tareas vencidas: {overdue_tasks}. Próximas: {due_soon}. Resolver vencimientos puede evitar recargos o compras de urgencia.")
    else:
        lines.append("- No hay alertas fuertes por tareas con los datos cargados.")

    lines.extend([
        "",
        "Recomendaciones concretas:",
        "1. Revisar primero las categorías que subieron frente al mes anterior, no solo la categoría más grande.",
        "2. Si hay saldos a favor, decidir si se conservan para el período siguiente o se aplican a una deuda compatible.",
        "3. Antes de cerrar el mes, confirmar pagos anticipados, abonos y gastos fijos generados.",
        "4. Si hay gastos inusuales, agregar notas o categoría precisa para que el próximo análisis no los trate como patrón permanente.",
        "",
        "Preguntas para revisar en el hogar:",
        "- ¿Qué gasto subió por necesidad real y cuál por repetición o falta de planificación?",
        "- ¿Hay algún pago o abono pendiente que esté distorsionando el saldo entre integrantes?",
        "- ¿Los gastos fijos cargados siguen representando los montos reales del mes?",
    ])

    if ratio > 70:
        lines.append("- Alerta prudente: el gasto común está consumiendo una parte alta de los ingresos declarados. Revisar servicios, compras repetidas y compromisos fijos antes de sumar nuevos gastos.")
    elif ratio < 35 and total_income > 0:
        lines.append("- Hay margen aparente, pero solo es real si los gastos personales y deudas fuera del hogar no absorben ese excedente.")

    return (f"Informe del hogar · {month}", "\n".join(lines))



def _call_openai_chat(api_key: str, model: str, system_prompt: str, user_payload: dict[str, Any], json_mode: bool = False) -> str | None:
    if not api_key:
        return None
    body: dict[str, Any] = {
        "model": model,
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": json.dumps(user_payload, ensure_ascii=False)},
        ],
        "temperature": 0.25,
    }
    if json_mode:
        body["response_format"] = {"type": "json_object"}
    request = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=json.dumps(body).encode("utf-8"),
        headers={"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=50) as response:
            decoded = json.loads(response.read().decode("utf-8"))
        return decoded["choices"][0]["message"]["content"].strip()
    except Exception:
        return None


def generate_household_report(data: dict[str, Any], api_key: str | None = None, model: str = "gpt-4o-mini") -> tuple[str, str, dict[str, Any]]:
    title, fallback = _heuristic_household_report(data)
    evidence = {
        "scope": "hogar_compartido",
        "analysis_type": "monthly_manual",
        "base_currency": "ARS",
        "month": data.get("month"),
        "generated_with_api": False,
        "used_sections": ["summary", "previous_summary", "month_comparison", "expenses_by_category", "category_variations", "expense_anomalies", "active_debts", "credit_balances", "monthly_advance_payments", "fixed_expense_templates", "task_summary"],
        "data": data,
    }
    api_text = _call_openai_chat(
        api_key or "",
        model,
        "Sos un analista prudente de economía doméstica para un hogar en Argentina. La moneda base es ARS. Usá solo los datos recibidos: ingresos, gastos, variaciones, anomalías, deudas, saldos a favor, pagos anticipados, tareas y gastos fijos. No des recomendaciones financieras riesgosas ni de inversión. No inventes datos. Separá datos observados de inferencias. El análisis debe ser concreto: señalar categorías o movimientos específicos, riesgos domésticos, preguntas para revisar en el hogar y próximos pasos accionables en español rioplatense.",
        data,
    )
    if api_text:
        evidence["generated_with_api"] = True
        evidence["model"] = model
        return title, api_text, evidence
    evidence["model"] = "heuristic-fallback"
    return title, fallback, evidence


def _heuristic_weekly_report(data: dict[str, Any], external_context: dict[str, Any]) -> tuple[str, str, list[dict[str, Any]]]:
    summary = data.get("summary", {})
    period = data.get("period", {})
    categories = data.get("expenses_by_category", [])
    category_variations = data.get("category_variations", [])
    anomalies = data.get("expense_anomalies", [])
    active_debts = data.get("active_debts", [])
    credit_balances = data.get("credit_balances", [])
    advance_payments = data.get("monthly_advance_payments", [])
    fixed_summary = data.get("fixed_expense_summary", {})
    comparison = data.get("month_comparison", {})
    task_summary = data.get("task_summary", {})
    week_key = period.get("week_key") or "período actual"

    total_income = _as_float(summary.get("total_income"))
    total_expenses = _as_float(summary.get("total_shared_expenses"))
    weekly_total = _as_float(data.get("weekly_expenses_total"))
    previous_weekly_total = _as_float(data.get("previous_weekly_expenses_total"))
    weekly_delta = weekly_total - previous_weekly_total
    debt_total = sum(_as_float(item.get("remaining_amount")) for item in active_debts)
    credit_total = sum(_as_float(item.get("remaining_amount")) for item in credit_balances)
    pending_advance_total = sum(_as_float(item.get("amount")) for item in advance_payments if str(item.get("status")) == "pending")
    ratio = (total_expenses / total_income * 100) if total_income else 0
    biggest = categories[0] if categories else None
    fixed_expected = _as_float(fixed_summary.get("active_total_expected"))
    fixed_count = int(fixed_summary.get("active_count") or 0)

    previous_map = {item.get("category"): _as_float(item.get("amount")) for item in data.get("previous_expenses_by_category", [])}
    increases = []
    for item in categories:
        category = item.get("category")
        amount = _as_float(item.get("amount"))
        previous = previous_map.get(category, 0)
        if previous > 0 and amount > previous * 1.15:
            increases.append({"category": category, "amount": amount, "previous": previous, "variation": ((amount - previous) / previous * 100)})

    dolar_notes = []
    for indicator in external_context.get("indicators", [])[:3]:
        name = indicator.get("name") or indicator.get("label")
        sell = indicator.get("sell")
        if sell:
            dolar_notes.append(f"{name}: referencia de venta cercana a {_money(_as_float(sell))} por USD")

    tips: list[dict[str, Any]] = []
    if increases:
        top = sorted(increases, key=lambda item: item["variation"], reverse=True)[0]
        tips.append(_fallback_tip(
            "Suba concreta para revisar",
            f"{top['category']} subió aproximadamente {top['variation']:.0f}% frente al período anterior registrado. Revisen movimientos de esa categoría antes de pensar en recortes generales.",
            "warning",
            "alerta",
        ))
    elif biggest:
        tips.append(_fallback_tip(
            "Categoría dominante",
            f"El mayor peso aparece en {biggest.get('category')}, con {_money(_as_float(biggest.get('amount')))}. Revisen si ese monto responde a un gasto fijo, compra puntual o repetición semanal.",
            "info",
            "consumo",
        ))
    if anomalies:
        top_anomaly = anomalies[0]
        tips.append(_fallback_tip(
            "Movimiento inusual",
            f"{top_anomaly.get('category')} registra {_money(_as_float(top_anomaly.get('amount')))} y conviene clasificarlo bien para no confundirlo con un patrón mensual.",
            "warning",
            "alerta",
        ))
    if debt_total > 0:
        tips.append(_fallback_tip(
            "Ordenar deudas antes del cierre",
            f"Quedan deudas activas/parciales por {_money(debt_total)}. Conviene registrar abonos y confirmar pagos antes de cerrar el período.",
            "info",
            "deudas",
        ))
    if credit_total > 0:
        tips.append(_fallback_tip(
            "Saldo a favor disponible",
            f"Hay {_money(credit_total)} en saldos a favor. Mantenerlo separado del saldo provisorio y aplicarlo solo a deudas compatibles.",
            "success",
            "deudas",
        ))
    if int(task_summary.get("overdue_count") or 0) > 0:
        tips.append(_fallback_tip(
            "Tarea vencida",
            f"Hay {task_summary.get('overdue_count')} tarea(s) vencida(s). Resolverlas puede evitar recargos, compras de urgencia o discusiones innecesarias.",
            "danger",
            "tareas",
        ))
    if not tips:
        tips.append(_fallback_tip(
            "Sin alertas fuertes",
            "No aparecen alertas duras con los datos cargados. El siguiente paso útil es completar histórico, gastos fijos y abonos para afinar la comparación.",
            "success",
            "general",
        ))

    lines = [
        f"Análisis del hogar · {week_key}",
        "",
        "Diagnóstico breve:",
        "Moneda base: ARS. El dólar se considera solo como indicador contextual, no como reemplazo de los gastos cargados.",
        f"- Gastos comunes del mes: {_money(total_expenses)}. Ingresos declarados para reparto: {_money(total_income)}.",
    ]
    if total_income > 0:
        lines.append(f"- Los gastos comunes representan aproximadamente {ratio:.1f}% de los ingresos del hogar cargados para este mes.")
    if previous_weekly_total > 0:
        sign = "subió" if weekly_delta > 0 else "bajó" if weekly_delta < 0 else "se mantuvo"
        lines.append(f"- En el período analizado, el gasto {sign} {_money(abs(weekly_delta))} frente al período anterior comparable.")
    elif _as_float(comparison.get("previous_total_shared_expenses")) > 0:
        lines.append(f"- Frente al mes anterior, el gasto total varió {_money(abs(_as_float(comparison.get('expense_delta'))))}.")
    else:
        lines.append("- El histórico todavía es limitado; las comparaciones deben leerse como indicios, no como tendencia firme.")

    if biggest:
        lines.append(f"- Categoría de mayor peso: {biggest.get('category')}, con {_money(_as_float(biggest.get('amount')))}.")
    if increases:
        lines.append("Aumentos relativos detectados: " + ", ".join([f"{item['category']} ({item['variation']:.0f}%)" for item in increases[:3]]) + ".")
    if anomalies:
        lines.append("Movimientos inusuales a mirar: " + "; ".join([f"{item.get('category')} {_money(_as_float(item.get('amount')))}" for item in anomalies[:3]]) + ".")
    if fixed_count:
        lines.append(f"Gastos fijos activos esperados: {fixed_count}, por aproximadamente {_money(fixed_expected)}. Revisen si ya fueron generados para no duplicarlos.")
    if debt_total > 0 or credit_total > 0 or pending_advance_total > 0:
        lines.append(
            f"Deudas/saldos: deudas activas {_money(debt_total)}, saldos a favor {_money(credit_total)}, pagos anticipados pendientes {_money(pending_advance_total)}."
        )
    if dolar_notes:
        lines.append("Contexto económico consultado: " + "; ".join(dolar_notes) + ".")
    news = external_context.get("news") or []
    if news:
        lines.append(f"Se tomaron {len(news)} noticia(s) económicas como contexto general, sin usarlas como fuente única para decidir gastos.")

    lines.extend([
        "",
        "Lectura doméstica:",
        "El objetivo no es producir culpa por gastar, sino distinguir gasto necesario, gasto fijo, movimiento inusual y deuda pendiente. Esa separación evita discutir sobre promedios cuando en realidad hubo un pago puntual o un saldo a favor sin aplicar.",
        "",
        "Recomendaciones accionables:",
        "1. Revisar las categorías que subieron, no solo el total del mes.",
        "2. Confirmar pagos anticipados y abonos antes del cierre para que los saldos no queden distorsionados.",
        "3. Si hay gastos fijos activos, generarlos una sola vez por período y ajustar montos reales.",
        "4. Si hay saldo a favor, decidir si se conserva o se aplica a una deuda compatible.",
        "",
        "Preguntas para conversar:",
        "- ¿Qué movimiento explica la mayor variación del período?",
        "- ¿Hay algún gasto fijo que cambió de monto y todavía está cargado con valor viejo?",
        "- ¿Queda algún pago pendiente de confirmar que pueda cambiar la lectura del saldo?",
        "",
        "Consejos visibles:",
    ])
    for idx, tip in enumerate(tips[:4], start=1):
        lines.append(f"{idx}. {tip['title']}: {tip['body']}")
    return f"Informe IA del hogar · {week_key}", "\n".join(lines), tips[:4]



def generate_weekly_household_report(
    data: dict[str, Any],
    external_context: dict[str, Any],
    api_key: str | None = None,
    model: str = "gpt-4o-mini",
) -> tuple[str, str, dict[str, Any]]:
    title, fallback_content, fallback_tips = _heuristic_weekly_report(data, external_context)
    evidence: dict[str, Any] = {
        "scope": "hogar_compartido",
        "analysis_type": "weekly_contextual",
        "base_currency": "ARS",
        "generated_with_api": False,
        "month": data.get("month"),
        "period": data.get("period"),
        "model": "heuristic-fallback",
        "used_sections": [
            "summary",
            "previous_summary",
            "month_comparison",
            "expenses_by_category",
            "previous_expenses_by_category",
            "category_variations",
            "expense_anomalies",
            "active_debts",
            "credit_balances",
            "monthly_advance_payments",
            "fixed_expense_templates",
            "task_summary",
            "economic_context",
        ],
        "visible_tips": fallback_tips,
        "economic_context": external_context,
        "data": data,
    }
    payload = {
        "instructions": {
            "language": "es_AR",
            "base_currency": "ARS",
            "dollar_role": "contextual_only",
            "goal": "producir un análisis doméstico profundo, concreto y accionable, no una lista genérica",
            "must_analyze": [
                "variaciones frente al período anterior",
                "categorías que suben o aparecen nuevas",
                "movimientos inusuales",
                "deudas, abonos, pagos anticipados y saldos a favor",
                "gastos fijos esperados o generados",
                "tareas vencidas o próximas",
                "riesgos domésticos y preguntas para conversar"
            ],
            "avoid": ["recomendaciones de inversión", "comprar dólares", "tomar deuda", "consejos financieros riesgosos", "frases genéricas sin datos concretos"],
            "output_json_schema": {
                "title": "string",
                "full_report": "string",
                "visible_tips": [
                    {"title": "string", "body": "string", "level": "info|success|warning|danger", "kind": "consumo|deudas|tareas|contexto|general"}
                ],
            },
        },
        "household_data": data,
        "economic_context": external_context,
    }
    api_text = _call_openai_chat(
        api_key or "",
        model,
        "Sos un analista prudente de economía doméstica para un hogar en Argentina. La moneda base del sistema es ARS. Usá el dólar únicamente como indicador contextual. Relacioná gastos comunes, variaciones históricas, anomalías, deudas, saldos a favor, pagos anticipados, gastos fijos, tareas e indicadores externos. Respondé solo JSON válido con title, full_report y visible_tips. No inventes datos, no des consejos de inversión ni frases genéricas. Indicá qué es dato observado y qué es inferencia prudente.",
        payload,
        json_mode=True,
    )
    if api_text:
        try:
            parsed = json.loads(api_text)
            tips = parsed.get("visible_tips") or fallback_tips
            if not isinstance(tips, list):
                tips = fallback_tips
            normalized_tips = []
            for item in tips[:4]:
                if isinstance(item, dict):
                    normalized_tips.append(
                        {
                            "title": str(item.get("title") or "Consejo IA"),
                            "body": str(item.get("body") or "Revisá el informe completo."),
                            "level": str(item.get("level") or "info"),
                            "kind": str(item.get("kind") or "general"),
                            "valid_until": item.get("valid_until") or (date.today() + timedelta(days=7)).isoformat(),
                        }
                    )
            evidence["generated_with_api"] = True
            evidence["model"] = model
            evidence["visible_tips"] = normalized_tips or fallback_tips
            return str(parsed.get("title") or title), str(parsed.get("full_report") or fallback_content), evidence
        except Exception:
            pass
    return title, fallback_content, evidence


def generate_task_project_analysis(data: dict[str, Any], api_key: str | None = None, model: str = "gpt-4o-mini") -> dict[str, Any]:
    """Analiza una tarea/proyecto doméstico sin convertirlo en consejo financiero riesgoso.

    Devuelve estructura estable para guardar trazabilidad en la tarea. Si no hay API,
    genera un fallback local útil con los datos que sí están cargados.
    """
    task = data.get("task", {})
    title = _safe_text(task.get("title")) or "Proyecto del hogar"
    kind = _safe_text(task.get("source_type")) or "manual"
    budget = float(task.get("budget_amount") or 0)
    links = task.get("product_links") or []
    sources = task.get("preferred_sources") or []
    frequency = _safe_text(task.get("tracking_frequency")) or "manual"

    fallback_lines = [
        f"Seguimiento IA para: {title}",
        "",
        "Moneda base: ARS. Los precios detectados deben tomarse como orientativos y variables.",
    ]
    if kind in {"purchase", "project"}:
        fallback_lines.append("Tipo: proyecto de compra / investigación doméstica.")
    elif kind == "savings":
        fallback_lines.append("Tipo: plan de ahorro o meta doméstica.")
    elif kind == "payment":
        fallback_lines.append("Tipo: pago pendiente o vencimiento.")
    else:
        fallback_lines.append("Tipo: tarea común del hogar.")
    if budget > 0:
        fallback_lines.append(f"Presupuesto cargado: {_money(budget)}.")
    if links:
        fallback_lines.append(f"Links cargados para revisar: {len(links)}.")
    if sources:
        fallback_lines.append("Fuentes o tiendas sugeridas: " + ", ".join(str(x) for x in sources[:4]) + ".")
    fallback_lines.extend([
        "",
        "Recomendación prudente:",
        "1. Comparar precio final con envío, garantía y disponibilidad real antes de decidir.",
        "2. Evitar comprar por impulso: si supera el presupuesto, mantenerlo como seguimiento y revisar en la próxima actualización.",
        "3. Guardar links y fecha de revisión para poder ver si sube o baja con el tiempo.",
    ])
    if frequency != "manual":
        fallback_lines.append(f"Frecuencia configurada para seguimiento: {frequency}.")

    fallback = {
        "summary": "\n".join(fallback_lines),
        "recommendation": "Comparar con calma, revisar disponibilidad y no superar el presupuesto sin acuerdo del hogar.",
        "price_min": None,
        "price_max": None,
        "availability": "no_verificada",
        "warnings": ["Sin consulta externa efectiva: resultado basado en datos cargados."],
        "evidence": {
            "scope": "tarea_proyecto_hogar",
            "analysis_type": "task_project_followup",
            "base_currency": "ARS",
            "generated_with_api": False,
            "model": "heuristic-fallback",
            "reviewed_links": links,
            "preferred_sources": sources,
            "tracking_frequency": frequency,
            "prices_detected": [],
            "data": data,
        },
    }

    payload = {
        "instructions": {
            "language": "es_AR",
            "base_currency": "ARS",
            "dollar_role": "contextual_only",
            "task": "Analizar un proyecto/tarea del hogar con links o fuentes cargadas por el usuario.",
            "avoid": ["compras impulsivas", "recomendaciones financieras riesgosas", "inventar precios", "inventar disponibilidad"],
            "output_json_schema": {
                "summary": "string",
                "recommendation": "string",
                "price_min": "number|null",
                "price_max": "number|null",
                "availability": "string",
                "warnings": ["string"],
                "reviewed_links": ["string"],
                "prices_detected": [{"source": "string", "price_ars": "number|null", "note": "string"}],
            },
        },
        "project_data": data,
    }
    api_text = _call_openai_chat(
        api_key or "",
        model,
        "Sos un asistente prudente para compras y proyectos domésticos en Argentina. La moneda base es ARS. Si no podés verificar precio o disponibilidad, decilo explícitamente. No inventes precios ni stock. Respondé solo JSON válido con summary, recommendation, price_min, price_max, availability, warnings, reviewed_links y prices_detected.",
        payload,
        json_mode=True,
    )
    if api_text:
        try:
            parsed = json.loads(api_text)
            evidence = {
                "scope": "tarea_proyecto_hogar",
                "analysis_type": "task_project_followup",
                "base_currency": "ARS",
                "generated_with_api": True,
                "model": model,
                "reviewed_links": parsed.get("reviewed_links") or links,
                "preferred_sources": sources,
                "tracking_frequency": frequency,
                "prices_detected": parsed.get("prices_detected") or [],
                "availability": parsed.get("availability"),
                "warnings": parsed.get("warnings") or [],
                "data": data,
            }
            summary = str(parsed.get("summary") or fallback["summary"])
            recommendation = str(parsed.get("recommendation") or fallback["recommendation"])
            return {
                "summary": summary,
                "recommendation": recommendation,
                "price_min": parsed.get("price_min"),
                "price_max": parsed.get("price_max"),
                "availability": parsed.get("availability") or "no_verificada",
                "warnings": parsed.get("warnings") or [],
                "evidence": evidence,
            }
        except Exception:
            pass
    return fallback
