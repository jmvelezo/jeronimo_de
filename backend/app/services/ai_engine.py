import json
import urllib.request
from datetime import date, timedelta
from typing import Any


def _money(value: float) -> str:
    return f"$ {value:,.0f}".replace(",", ".")


def _safe_text(value: Any) -> str:
    return str(value or "").strip()


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
    active_debts = data.get("active_debts", [])
    task_summary = data.get("task_summary", {})
    month = data.get("month", "mes actual")

    total_income = float(summary.get("total_income") or 0)
    total_expenses = float(summary.get("total_shared_expenses") or 0)
    ratio = (total_expenses / total_income * 100) if total_income else 0
    biggest = expenses_by_category[0] if expenses_by_category else None
    debt_total = sum(float(item.get("remaining_amount") or 0) for item in active_debts)
    overdue_tasks = int(task_summary.get("overdue_count") or 0)
    due_soon = int(task_summary.get("due_soon_count") or 0)

    lines = [
        f"Análisis del hogar para {month}",
        "",
        f"Los gastos comunes registrados suman {_money(total_expenses)} sobre ingresos declarados por {_money(total_income)}.",
    ]
    if total_income > 0:
        lines.append(f"Eso representa aproximadamente {ratio:.1f}% del ingreso común cargado para el reparto.")
    else:
        lines.append("Todavía faltan ingresos cargados para que el reparto y la lectura del mes sean más confiables.")

    if biggest:
        lines.append(f"La categoría con mayor peso es {_safe_text(biggest.get('category'))}, con {_money(float(biggest.get('amount') or 0))}.")

    if debt_total > 0:
        lines.append(f"Hay deudas activas del hogar por aproximadamente {_money(debt_total)}. Conviene priorizar su cancelación antes de generar nuevos acuerdos.")
    else:
        lines.append("No aparecen deudas activas relevantes en el hogar.")

    if overdue_tasks or due_soon:
        lines.append(f"También hay {overdue_tasks} tarea(s) vencida(s) y {due_soon} próxima(s). Esto puede convertirse en gasto o conflicto si no se atiende a tiempo.")

    lines.extend([
        "",
        "Recomendaciones:",
        "1. Revisar la categoría de mayor peso y separar gasto necesario de gasto evitable.",
        "2. Registrar pagos o abonos apenas ocurren para que el saldo entre integrantes no se distorsione.",
        "3. Cerrar el mes solo cuando ingresos, gastos, deudas y tareas principales estén revisados.",
        "4. Usar tareas comunes para vencimientos de servicios, compras grandes y acuerdos pendientes.",
    ])

    if ratio > 70:
        lines.append("5. Alerta: el gasto común está consumiendo una parte alta de los ingresos declarados. Conviene revisar servicios, compras repetidas y gastos recurrentes.")
    elif ratio < 35 and total_income > 0:
        lines.append("5. Hay margen aparente para proyectar ahorro común o adelantar pagos, siempre que los gastos personales no estén absorbiendo ese excedente.")

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
        "used_sections": ["summary", "expenses_by_category", "active_debts", "task_summary"],
        "data": data,
    }
    api_text = _call_openai_chat(
        api_key or "",
        model,
        "Sos un asistente de finanzas domésticas para un hogar en Argentina. La moneda base es ARS. El dólar solo puede usarse como contexto si aparece en los datos. Analizá solo datos comunes del hogar. No inventes gastos. No des recomendaciones financieras riesgosas. Devolvé recomendaciones claras, prudentes y accionables en español rioplatense.",
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
    previous_categories = data.get("previous_expenses_by_category", [])
    active_debts = data.get("active_debts", [])
    task_summary = data.get("task_summary", {})
    week_key = period.get("week_key") or "semana actual"

    total_income = float(summary.get("total_income") or 0)
    total_expenses = float(summary.get("total_shared_expenses") or 0)
    debt_total = sum(float(item.get("remaining_amount") or 0) for item in active_debts)
    ratio = (total_expenses / total_income * 100) if total_income else 0
    biggest = categories[0] if categories else None

    previous_map = {item.get("category"): float(item.get("amount") or 0) for item in previous_categories}
    increases = []
    for item in categories:
        category = item.get("category")
        amount = float(item.get("amount") or 0)
        previous = previous_map.get(category, 0)
        if previous > 0 and amount > previous * 1.15:
            increases.append({"category": category, "amount": amount, "previous": previous, "variation": ((amount - previous) / previous * 100)})

    dolar_notes = []
    for indicator in external_context.get("indicators", [])[:3]:
        name = indicator.get("name") or indicator.get("label")
        sell = indicator.get("sell")
        if sell:
            dolar_notes.append(f"{name}: referencia de venta cercana a {_money(float(sell))} por USD")

    tips: list[dict[str, Any]] = []
    if biggest:
        tips.append(_fallback_tip(
            "Mirar el gasto que más pesa",
            f"Esta semana el mayor peso aparece en {biggest.get('category')}, con {_money(float(biggest.get('amount') or 0))}. Revisen si conviene agrupar compras o poner un tope semanal.",
            "warning" if ratio > 65 else "info",
            "consumo",
        ))
    if increases:
        top = sorted(increases, key=lambda item: item["variation"], reverse=True)[0]
        tips.append(_fallback_tip(
            "Suba semanal detectada",
            f"{top['category']} subió aproximadamente {top['variation']:.0f}% frente al período anterior registrado. No implica recortar todo, pero sí revisar frecuencia y necesidad.",
            "warning",
            "alerta",
        ))
    if debt_total > 0:
        tips.append(_fallback_tip(
            "Ordenar deudas del hogar",
            f"Quedan deudas comunes activas por {_money(debt_total)}. Conviene registrar abonos chicos apenas ocurran para que el saldo no se vuelva confuso.",
            "info",
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
            "Semana estable",
            "No aparecen alertas fuertes con los datos cargados. Mantengan gastos, deudas y tareas al día para que el análisis sea más fino.",
            "success",
            "general",
        ))

    lines = [
        f"Análisis semanal del hogar · {week_key}",
        "",
        "Moneda base: ARS. El dólar se considera solo como indicador contextual, no como reemplazo de los gastos cargados.",
        f"Gastos comunes del mes cargados: {_money(total_expenses)}. Ingresos declarados para reparto: {_money(total_income)}.",
    ]
    if total_income > 0:
        lines.append(f"Los gastos comunes representan aproximadamente {ratio:.1f}% de los ingresos del hogar cargados para este mes.")
    if biggest:
        lines.append(f"La categoría común de mayor peso es {biggest.get('category')}, con {_money(float(biggest.get('amount') or 0))}.")
    if increases:
        lines.append("Se detectaron aumentos relativos frente al período anterior en: " + ", ".join([f"{item['category']} ({item['variation']:.0f}%)" for item in increases[:3]]) + ".")
    if dolar_notes:
        lines.append("Contexto económico consultado: " + "; ".join(dolar_notes) + ".")
    news = external_context.get("news") or []
    if news:
        lines.append(f"También se tomaron {len(news)} noticia(s) económicas como contexto general, sin usarlas como fuente única para decidir gastos.")
    lines.extend([
        "",
        "Lectura doméstica:",
        "La recomendación no es convertir el hogar en una planilla de castigo, sino detectar dónde se repiten pequeñas fugas, qué deuda conviene ordenar y qué tarea pendiente puede transformarse en gasto.",
        "",
        "Consejos visibles para esta semana:",
    ])
    for idx, tip in enumerate(tips[:4], start=1):
        lines.append(f"{idx}. {tip['title']}: {tip['body']}")
    lines.extend([
        "",
        "Próximo paso sugerido:",
        "Revisar el gasto de mayor peso, completar tareas vencidas y registrar abonos/deudas antes del cierre mensual.",
    ])
    return f"Informe semanal IA · {week_key}", "\n".join(lines), tips[:4]


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
            "expenses_by_category",
            "previous_expenses_by_category",
            "active_debts",
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
            "avoid": ["recomendaciones de inversión", "comprar dólares", "tomar deuda", "consejos financieros riesgosos"],
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
        "Sos un analista prudente de economía doméstica para un hogar en Argentina. La moneda base del sistema es ARS. Usá el dólar únicamente como indicador contextual. Relacioná gastos comunes, deudas, tareas e indicadores externos. Respondé solo JSON válido con title, full_report y visible_tips. No inventes datos y no des recomendaciones financieras riesgosas.",
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
