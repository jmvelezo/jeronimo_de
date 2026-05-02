from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from .config import get_settings
from .database import create_db_and_tables
from .routers import ai, app_info, auth, backup, finance, household, tasks

settings = get_settings()

app = FastAPI(title=settings.app_name, version="0.5.6-R16")

# Flutter Web corre en un puerto local variable (localhost:xxxxx).
# Para desarrollo local no usamos cookies ni credenciales del navegador;
# el acceso se hace con token Bearer. Por eso allow_credentials=False
# evita bloqueos de CORS cuando allow_origins es "*".
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
    expose_headers=["*"],
)


@app.on_event("startup")
def on_startup() -> None:
    create_db_and_tables()



@app.get("/", include_in_schema=False)
def root() -> dict:
    return {
        "ok": True,
        "app": settings.app_name,
        "version": "0.5.6-R16",
        "message": "Jeronimo Dé API está funcionando. R16 compacta tareas y agrega proyectos de compra/ahorro con seguimiento IA.",
        "health": "/health",
        "docs": "/docs",
    }

@app.get("/health")
def health() -> dict:
    return {"ok": True, "app": settings.app_name, "version": "0.5.6-R16"}


@app.get("/debug/cors")
def debug_cors() -> dict:
    return {"ok": True, "cors_origins": settings.cors_origin_list}


app.include_router(app_info.router)
app.include_router(auth.router)
app.include_router(backup.router)
app.include_router(household.router)
app.include_router(finance.router)
app.include_router(tasks.router)
app.include_router(ai.router)
