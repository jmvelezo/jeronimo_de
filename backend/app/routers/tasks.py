import json
from datetime import date as Date, datetime, timezone
from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select
from ..database import get_session
from ..config import get_settings
from ..models import HouseholdTask, Member, TaskPriority, TaskRepeatRule, TaskStatus
from ..services.ai_engine import generate_task_project_analysis
from ..schemas import HouseholdTaskCreate, HouseholdTaskRead, HouseholdTaskSummary, HouseholdTaskUpdate
from .auth import get_current_member

router = APIRouter(prefix="/tasks", tags=["tasks"])


def ensure_member(session: Session, household_id: int, member_id: int | None) -> Member | None:
    if member_id is None:
        return None
    member = session.get(Member, member_id)
    if not member or member.household_id != household_id or not member.is_active:
        raise HTTPException(status_code=404, detail="Responsable no encontrado en este hogar")
    return member


def get_task(session: Session, household_id: int, task_id: int) -> HouseholdTask:
    task = session.get(HouseholdTask, task_id)
    if not task or task.household_id != household_id:
        raise HTTPException(status_code=404, detail="Tarea no encontrada")
    return task


def add_month(value: Date) -> Date:
    year = value.year + (1 if value.month == 12 else 0)
    month = 1 if value.month == 12 else value.month + 1
    # mantener día cuando se pueda; si no, bajar hasta día válido
    day = value.day
    while day > 27:
        try:
            return Date(year, month, day)
        except ValueError:
            day -= 1
    return Date(year, month, day)


def _safe_json(raw: str | None) -> dict:
    if not raw:
        return {}
    try:
        value = json.loads(raw)
        return value if isinstance(value, dict) else {"value": value}
    except Exception:
        return {"raw": raw}


def task_to_read(task: HouseholdTask) -> HouseholdTaskRead:
    today = Date.today()
    is_pending = task.status == TaskStatus.pending
    is_overdue = bool(is_pending and task.due_date and task.due_date < today)
    is_due_soon = bool(is_pending and task.due_date and 0 <= (task.due_date - today).days <= 3)
    alert_due = bool(is_pending and task.alert_date and task.alert_date <= today)
    if is_overdue:
        alert_level = "overdue"
    elif task.priority in (TaskPriority.high, TaskPriority.urgent) or alert_due:
        alert_level = "high"
    elif is_due_soon:
        alert_level = "soon"
    else:
        alert_level = "normal"
    return HouseholdTaskRead(
        id=task.id or 0,
        household_id=task.household_id,
        title=task.title,
        description=task.description,
        assigned_member_id=task.assigned_member_id,
        due_date=task.due_date,
        alert_date=task.alert_date,
        priority=task.priority,
        status=task.status,
        repeat_rule=task.repeat_rule,
        source_type=task.source_type,
        budget_amount=task.budget_amount or 0,
        product_links=task.product_links or "",
        preferred_sources=task.preferred_sources or "",
        tracking_frequency=task.tracking_frequency or "manual",
        last_ai_check_at=task.last_ai_check_at,
        last_ai_summary=task.last_ai_summary or "",
        last_ai_evidence=_safe_json(task.last_ai_evidence_json),
        created_by_member_id=task.created_by_member_id,
        completed_by_member_id=task.completed_by_member_id,
        completed_at=task.completed_at,
        created_at=task.created_at,
        updated_at=task.updated_at,
        is_overdue=is_overdue,
        is_due_soon=is_due_soon,
        alert_level=alert_level,
    )


@router.get("/summary", response_model=HouseholdTaskSummary)
def task_summary(current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    rows = session.exec(select(HouseholdTask).where(HouseholdTask.household_id == current_member.household_id)).all()
    reads = [task_to_read(row) for row in rows]
    pending = [item for item in reads if item.status == TaskStatus.pending]
    return HouseholdTaskSummary(
        pending_count=len(pending),
        overdue_count=len([item for item in pending if item.is_overdue]),
        due_soon_count=len([item for item in pending if item.is_due_soon]),
        high_priority_count=len([item for item in pending if item.alert_level in {"high", "overdue"}]),
        assigned_to_me_count=len([item for item in pending if item.assigned_member_id == current_member.id]),
    )


@router.get("", response_model=list[HouseholdTaskRead])
def list_tasks(
    include_done: bool = False,
    assigned_to_me: bool = False,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    query = select(HouseholdTask).where(HouseholdTask.household_id == current_member.household_id)
    if not include_done:
        query = query.where(HouseholdTask.status == TaskStatus.pending)
    if assigned_to_me:
        query = query.where(HouseholdTask.assigned_member_id == current_member.id)
    rows = session.exec(query.order_by(HouseholdTask.due_date.asc(), HouseholdTask.priority.desc(), HouseholdTask.id.desc())).all()
    return [task_to_read(row) for row in rows]


@router.post("", response_model=HouseholdTaskRead)
def create_task(
    payload: HouseholdTaskCreate,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    ensure_member(session, current_member.household_id, payload.assigned_member_id)
    task = HouseholdTask(
        household_id=current_member.household_id,
        title=payload.title.strip(),
        description=payload.description.strip(),
        assigned_member_id=payload.assigned_member_id,
        due_date=payload.due_date,
        alert_date=payload.alert_date,
        priority=payload.priority,
        repeat_rule=payload.repeat_rule,
        source_type=(payload.source_type.strip() or "manual"),
        budget_amount=payload.budget_amount or 0,
        product_links=payload.product_links.strip(),
        preferred_sources=payload.preferred_sources.strip(),
        tracking_frequency=(payload.tracking_frequency.strip() or "manual"),
        created_by_member_id=current_member.id or 0,
    )
    session.add(task)
    session.commit()
    session.refresh(task)
    return task_to_read(task)


@router.patch("/{task_id}", response_model=HouseholdTaskRead)
def update_task(
    task_id: int,
    payload: HouseholdTaskUpdate,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    task = get_task(session, current_member.household_id, task_id)
    ensure_member(session, current_member.household_id, payload.assigned_member_id)
    if payload.title is not None:
        task.title = payload.title.strip()
    if payload.description is not None:
        task.description = payload.description.strip()
    if payload.assigned_member_id is not None:
        task.assigned_member_id = payload.assigned_member_id
    if payload.due_date is not None:
        task.due_date = payload.due_date
    if payload.alert_date is not None:
        task.alert_date = payload.alert_date
    if payload.priority is not None:
        task.priority = payload.priority
    if payload.repeat_rule is not None:
        task.repeat_rule = payload.repeat_rule
    if payload.source_type is not None:
        task.source_type = payload.source_type.strip() or "manual"
    if payload.budget_amount is not None:
        task.budget_amount = payload.budget_amount
    if payload.product_links is not None:
        task.product_links = payload.product_links.strip()
    if payload.preferred_sources is not None:
        task.preferred_sources = payload.preferred_sources.strip()
    if payload.tracking_frequency is not None:
        task.tracking_frequency = payload.tracking_frequency.strip() or "manual"
    if payload.status is not None:
        task.status = payload.status
        if payload.status == TaskStatus.done:
            task.completed_by_member_id = current_member.id
            task.completed_at = datetime.now(timezone.utc)
        elif payload.status == TaskStatus.pending:
            task.completed_by_member_id = None
            task.completed_at = None
    task.updated_at = datetime.now(timezone.utc)
    session.add(task)
    session.commit()
    session.refresh(task)
    return task_to_read(task)


@router.post("/{task_id}/complete", response_model=HouseholdTaskRead)
def complete_task(task_id: int, current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    task = get_task(session, current_member.household_id, task_id)
    task.status = TaskStatus.done
    task.completed_by_member_id = current_member.id
    task.completed_at = datetime.now(timezone.utc)
    task.updated_at = datetime.now(timezone.utc)
    session.add(task)
    session.commit()
    session.refresh(task)

    if task.repeat_rule == TaskRepeatRule.monthly and task.due_date is not None:
        next_due = add_month(task.due_date)
        next_alert = add_month(task.alert_date) if task.alert_date else None
        next_task = HouseholdTask(
            household_id=task.household_id,
            title=task.title,
            description=task.description,
            assigned_member_id=task.assigned_member_id,
            due_date=next_due,
            alert_date=next_alert,
            priority=task.priority,
            repeat_rule=task.repeat_rule,
            source_type="recurrente",
            created_by_member_id=current_member.id or 0,
        )
        session.add(next_task)
        session.commit()
    return task_to_read(task)


@router.post("/{task_id}/ai-refresh", response_model=HouseholdTaskRead)
def refresh_task_ai(task_id: int, current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    task = get_task(session, current_member.household_id, task_id)
    settings = get_settings()
    members = session.exec(select(Member).where(Member.household_id == current_member.household_id)).all()
    payload = {
        "task": {
            "id": task.id,
            "title": task.title,
            "description": task.description,
            "source_type": task.source_type,
            "budget_amount": task.budget_amount or 0,
            "product_links": [line.strip() for line in (task.product_links or "").splitlines() if line.strip()],
            "preferred_sources": [line.strip() for line in (task.preferred_sources or "").splitlines() if line.strip()],
            "tracking_frequency": task.tracking_frequency or "manual",
            "due_date": task.due_date.isoformat() if task.due_date else None,
            "priority": task.priority.value if hasattr(task.priority, "value") else str(task.priority),
        },
        "household": {
            "id": current_member.household_id,
            "members": [{"id": member.id, "name": member.name, "role": member.role.value if hasattr(member.role, "value") else str(member.role)} for member in members],
        },
        "rules": {
            "base_currency": "ARS",
            "dollar_role": "contextual_only",
            "avoid": ["compras impulsivas", "recomendaciones financieras riesgosas"],
        },
    }
    result = generate_task_project_analysis(
        payload,
        api_key=settings.openai_api_key,
        model=settings.openai_model,
    )
    task.last_ai_check_at = datetime.now(timezone.utc)
    task.last_ai_summary = result.get("summary", "")
    task.last_ai_evidence_json = json.dumps(result.get("evidence", {}), ensure_ascii=False)
    task.updated_at = datetime.now(timezone.utc)
    session.add(task)
    session.commit()
    session.refresh(task)
    return task_to_read(task)


@router.post("/{task_id}/cancel", response_model=HouseholdTaskRead)
def cancel_task(task_id: int, current_member: Member = Depends(get_current_member), session: Session = Depends(get_session)):
    task = get_task(session, current_member.household_id, task_id)
    task.status = TaskStatus.cancelled
    task.updated_at = datetime.now(timezone.utc)
    session.add(task)
    session.commit()
    session.refresh(task)
    return task_to_read(task)
