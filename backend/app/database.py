from pathlib import Path
from sqlalchemy import text
from sqlmodel import SQLModel, Session, create_engine
from .config import get_settings

settings = get_settings()

database_url = settings.sqlalchemy_database_url
connect_args = {}
if database_url.startswith("sqlite"):
    connect_args = {"check_same_thread": False}
    Path("data").mkdir(parents=True, exist_ok=True)

engine = create_engine(database_url, echo=False, connect_args=connect_args, pool_pre_ping=True)


def _table_columns(conn, table_name: str) -> set[str]:
    if settings.sqlalchemy_database_url.startswith("sqlite"):
        rows = conn.execute(text(f"PRAGMA table_info({table_name})")).fetchall()
        return {row[1] for row in rows}
    rows = conn.execute(
        text(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_schema='public' AND table_name=:table_name"
        ),
        {"table_name": table_name},
    ).fetchall()
    return {row[0] for row in rows}


def _add_column_if_missing(conn, table_name: str, column_name: str, ddl: str) -> None:
    if column_name in _table_columns(conn, table_name):
        return
    conn.execute(text(f"ALTER TABLE {table_name} ADD COLUMN {column_name} {ddl}"))


def _ensure_lightweight_migrations() -> None:
    """Pequeñas migraciones tolerantes para bases ya creadas.

    SQLModel crea tablas nuevas, pero no agrega columnas en bases existentes.
    Esta función agrega solo columnas simples y necesarias, sin borrar datos.
    """
    with engine.begin() as conn:
        _add_column_if_missing(conn, "householdperiodsettings", "active_month_override", "VARCHAR(7)")

        if not settings.sqlalchemy_database_url.startswith("sqlite"):
            return

        rows = conn.execute(text("PRAGMA table_info(householdaisettings)")).fetchall()
        existing = {row[1] for row in rows}
        if rows and "analysis_frequency" not in existing:
            conn.execute(text("ALTER TABLE householdaisettings ADD COLUMN analysis_frequency VARCHAR(20) DEFAULT 'weekly'"))

        payment_rows = conn.execute(text("PRAGMA table_info(debtpayment)")).fetchall()
        payment_existing = {row[1] for row in payment_rows}
        if payment_rows:
            additions = {
                "received_by_member_id": "INTEGER",
                "applied_amount": "FLOAT DEFAULT 0",
                "credit_amount": "FLOAT DEFAULT 0",
                "status": "VARCHAR(20) DEFAULT 'confirmed'",
                "rejected_reason": "VARCHAR DEFAULT ''",
                "confirmed_by_member_id": "INTEGER",
                "confirmed_at": "DATETIME",
                "updated_at": "DATETIME",
            }
            for column, ddl in additions.items():
                if column not in payment_existing:
                    conn.execute(text(f"ALTER TABLE debtpayment ADD COLUMN {column} {ddl}"))
            conn.execute(text("UPDATE debtpayment SET status = COALESCE(status, 'confirmed')"))
            conn.execute(text("UPDATE debtpayment SET applied_amount = amount WHERE applied_amount IS NULL OR applied_amount = 0"))
            conn.execute(text("""
                UPDATE debtpayment
                SET received_by_member_id = (SELECT creditor_member_id FROM debt WHERE debt.id = debtpayment.debt_id)
                WHERE received_by_member_id IS NULL
            """))



        task_rows = conn.execute(text("PRAGMA table_info(householdtask)")).fetchall()
        task_existing = {row[1] for row in task_rows}
        if task_rows:
            task_additions = {
                "budget_amount": "FLOAT DEFAULT 0",
                "product_links": "VARCHAR DEFAULT ''",
                "preferred_sources": "VARCHAR DEFAULT ''",
                "tracking_frequency": "VARCHAR(20) DEFAULT 'manual'",
                "last_ai_check_at": "DATETIME",
                "last_ai_summary": "VARCHAR DEFAULT ''",
                "last_ai_evidence_json": "VARCHAR DEFAULT '{}'",
            }
            for column, ddl in task_additions.items():
                if column not in task_existing:
                    conn.execute(text(f"ALTER TABLE householdtask ADD COLUMN {column} {ddl}"))

        # R15: convertir el primer administrador histórico de cada hogar en propietario.
        member_rows = conn.execute(text("PRAGMA table_info(member)")).fetchall()
        if member_rows:
            households = conn.execute(text("SELECT id FROM household")).fetchall()
            for (household_id,) in households:
                owners = conn.execute(text("SELECT id FROM member WHERE household_id=:hid AND role='owner' AND is_active=1"), {"hid": household_id}).fetchall()
                if not owners:
                    first_admin = conn.execute(text("SELECT id FROM member WHERE household_id=:hid AND role='admin' ORDER BY id ASC LIMIT 1"), {"hid": household_id}).fetchone()
                    if first_admin:
                        conn.execute(text("UPDATE member SET role='owner' WHERE id=:mid"), {"mid": first_admin[0]})



def create_db_and_tables() -> None:
    SQLModel.metadata.create_all(engine)
    _ensure_lightweight_migrations()


def get_session():
    with Session(engine) as session:
        yield session
