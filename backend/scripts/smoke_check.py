from app.config import get_settings
from app.database import create_db_and_tables

settings = get_settings()
create_db_and_tables()
print({"ok": True, "app": settings.app_name, "env": settings.app_env, "database": settings.sqlalchemy_database_url.split('@')[-1]})
