from datetime import datetime, timezone
from fastapi import APIRouter
from ..config import get_settings
from ..schemas import AppCapabilities, AppSyncStatus

router = APIRouter(prefix="/app", tags=["app"])


@router.get("/capabilities", response_model=AppCapabilities)
def capabilities() -> AppCapabilities:
    settings = get_settings()
    return AppCapabilities(
        app=settings.app_name,
        version="0.5.6-R16B",
        modes=["personal_local", "hogar_compartido", "hibrido"],
        active_mode="hogar_compartido",
        advanced_configuration=True,
        notes=[
            "El módulo de hogar compartido usa la API y base del servidor.",
            "El modo personal local guarda perfil, cuentas, ingresos, gastos, deudas personales y configuración privada en el dispositivo.",
            "La configuración avanzada concentra servidor, miembros y opciones técnicas.",
            "La experiencia visual está reorganizada en navegación inferior, tarjetas y acciones simples.",
            "El modo personal ya incluye cuentas, ingresos, gastos, categorías, presupuestos, deudas y resumen mensual privado.",
            "El hogar compartido permite participación mensual por integrante para excluir temporalmente sin borrar historial.",
            "El sistema de tareas comunes permite responsables, vencimientos, alertas, prioridad y repetición mensual.",
            "La app conserva una última foto local de datos comunes para mostrar estado de sincronización y manejar caídas de conexión.",
            "La IA del hogar genera informes compartidos con trazabilidad de datos usados; la IA personal se conserva privada en el dispositivo.",
            "La UX básica oculta complejidad técnica, muestra errores amigables y deja servidor/Railway dentro de Configuración avanzada.",
            "La distribución queda preparada para Windows, Android APK/PWA, Railway/PostgreSQL y respaldo JSON del hogar compartido.",
            "El análisis semanal IA puede combinar datos internos, contexto económico argentino, dólar como indicador contextual y consejos visibles en Inicio.",
            "La moneda base del sistema es ARS; el dólar no reemplaza el cálculo de gastos comunes ni deudas internas.",
            "El análisis IA del hogar permite frecuencia manual, semanal, quincenal o mensual y día de ejecución configurable.",
            "La interfaz R12 prioriza navegación simplificada, estética púrpura/lavanda y una pantalla Inicio más clara.",
            "R14 agrega confirmación de abonos: los pagos quedan pendientes hasta que el receptor confirme, y los excedentes generan saldo a favor.",
            "R15 diferencia saldo provisorio y deuda formal, agrega pagos anticipados confirmables, período configurable y permisos de propietario/administrador operativo.",
            "R16 compacta tareas en escritorio/móvil y agrega proyectos de compra/ahorro con seguimiento IA y trazabilidad.",
        ],
    )


@router.get("/sync-status", response_model=AppSyncStatus)
def sync_status() -> AppSyncStatus:
    settings = get_settings()
    return AppSyncStatus(
        ok=True,
        app=settings.app_name,
        version="0.5.6-R16B",
        server_time=datetime.now(timezone.utc),
        sync_protocol="api-url-v1",
        shared_scope="hogar_compartido_servidor",
        personal_scope="local_dispositivo",
        message="Servidor disponible. Los datos comunes pueden sincronizarse; los datos personales permanecen locales.",
    )
