from __future__ import annotations

import json
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from typing import Any


def _fetch_json(url: str, timeout: int = 8) -> tuple[bool, Any, str | None]:
    request = urllib.request.Request(url, headers={"User-Agent": "Jeronimo-De/0.5"})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return True, json.loads(response.read().decode("utf-8")), None
    except Exception as exc:  # pragma: no cover - depende de internet externo
        return False, None, str(exc)


def _clean_number(value: Any) -> float | None:
    try:
        if value is None:
            return None
        if isinstance(value, str):
            value = value.replace(".", "").replace(",", ".") if "," in value else value
        return float(value)
    except Exception:
        return None


def fetch_argentina_economic_context(include_news: bool = True) -> dict[str, Any]:
    """Obtiene contexto económico externo liviano y tolerante a fallos.

    La moneda base del sistema es ARS. El dólar se conserva solo como indicador contextual,
    salvo que una deuda/gasto sea cargado explícitamente en otra moneda en futuras fases.
    """
    generated_at = datetime.now(timezone.utc).isoformat()
    indicators: list[dict[str, Any]] = []
    news: list[dict[str, Any]] = []
    traces: list[dict[str, Any]] = []

    dolar_sources = [
        ("dolar_oficial", "https://dolarapi.com/v1/dolares/oficial"),
        ("dolar_blue", "https://dolarapi.com/v1/dolares/blue"),
    ]
    for label, url in dolar_sources:
        ok, data, error = _fetch_json(url)
        trace = {"label": label, "url": url, "ok": ok}
        if error:
            trace["error"] = error[:180]
        traces.append(trace)
        if ok and isinstance(data, dict):
            indicators.append(
                {
                    "label": label,
                    "name": data.get("nombre") or label,
                    "currency": "ARS por USD",
                    "buy": _clean_number(data.get("compra")),
                    "sell": _clean_number(data.get("venta")),
                    "updated_at": data.get("fechaActualizacion"),
                    "use": "Indicador contextual para Argentina; no convierte gastos comunes automáticamente.",
                }
            )

    # Noticias livianas vía GDELT. Sirven como contexto narrativo, no como dato duro.
    if include_news:
        query = urllib.parse.quote('Argentina inflación alimentos tarifas economía hogar')
        url = (
            "https://api.gdeltproject.org/api/v2/doc/doc"
            f"?query={query}&mode=artlist&format=json&maxrecords=5&sort=datedesc"
        )
        ok, data, error = _fetch_json(url)
        trace = {"label": "noticias_contexto", "url": "GDELT economia hogar Argentina", "ok": ok}
        if error:
            trace["error"] = error[:180]
        traces.append(trace)
        if ok and isinstance(data, dict):
            for article in (data.get("articles") or [])[:5]:
                news.append(
                    {
                        "title": article.get("title"),
                        "source": article.get("sourceCountry") or article.get("domain"),
                        "url": article.get("url"),
                        "published_at": article.get("seendate"),
                        "use": "Contexto económico general; no se usa como fuente única para recomendaciones.",
                    }
                )

    return {
        "country": "Argentina",
        "base_currency": "ARS",
        "external_generated_at": generated_at,
        "indicators": indicators,
        "news": news,
        "traces": traces,
        "notes": [
            "El sistema calcula ingresos, gastos, deudas y reparto en ARS.",
            "El dólar se usa como indicador contextual; no reemplaza la moneda base del hogar.",
            "Las noticias se usan solo como contexto narrativo y deben contrastarse con los datos internos.",
        ],
    }
