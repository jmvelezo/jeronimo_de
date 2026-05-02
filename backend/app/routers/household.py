from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select
from ..database import get_session
from ..models import Member, MemberRole
from ..schemas import MemberActiveUpdate, MemberCreate, MemberRead, MemberUpdate
from ..services.security import hash_pin
from .auth import get_current_member, member_to_read

router = APIRouter(prefix="/household", tags=["household"])


def ensure_owner(current_member: Member) -> None:
    if current_member.role != MemberRole.owner:
        raise HTTPException(status_code=403, detail="Solo el propietario del hogar puede cambiar usuarios o permisos")


def is_operator(current_member: Member) -> bool:
    return current_member.role in {MemberRole.owner, MemberRole.admin}


def get_household_member(session: Session, household_id: int, member_id: int) -> Member:
    member = session.get(Member, member_id)
    if not member or member.household_id != household_id:
        raise HTTPException(status_code=404, detail="Integrante no encontrado")
    return member


@router.get("/members", response_model=list[MemberRead])
def list_members(
    include_inactive: bool = False,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    query = select(Member).where(Member.household_id == current_member.household_id)
    if not include_inactive:
        query = query.where(Member.is_active == True)
    members = session.exec(query.order_by(Member.is_active.desc(), Member.name.asc())).all()
    return [member_to_read(member) for member in members]


@router.post("/members", response_model=MemberRead)
def create_member(
    payload: MemberCreate,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    ensure_owner(current_member)
    existing = session.exec(
        select(Member).where(
            Member.household_id == current_member.household_id,
            Member.name == payload.name.strip(),
        )
    ).first()
    if existing and existing.is_active:
        raise HTTPException(status_code=409, detail="Ya existe un integrante activo con ese nombre")

    if payload.role == MemberRole.owner:
        raise HTTPException(status_code=400, detail="No se puede crear otro propietario desde esta pantalla")

    member = Member(
        household_id=current_member.household_id,
        name=payload.name.strip(),
        color=payload.color.strip() or "#7C3AED",
        role=payload.role,
        pin_hash=hash_pin(payload.pin),
        is_active=True,
    )
    session.add(member)
    session.commit()
    session.refresh(member)
    return member_to_read(member)


@router.patch("/members/{member_id}", response_model=MemberRead)
def update_member(
    member_id: int,
    payload: MemberUpdate,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    ensure_owner(current_member)
    member = get_household_member(session, current_member.household_id, member_id)
    if payload.name is not None:
        member.name = payload.name.strip()
    if payload.color is not None:
        member.color = payload.color.strip() or member.color
    if payload.role is not None:
        if member.id == current_member.id and payload.role != MemberRole.owner:
            raise HTTPException(status_code=409, detail="No podés quitarte el rol de propietario a vos mismo")
        active_owners = session.exec(
            select(Member).where(
                Member.household_id == current_member.household_id,
                Member.role == MemberRole.owner,
                Member.is_active == True,
            )
        ).all()
        if member.role == MemberRole.owner and payload.role != MemberRole.owner and len(active_owners) <= 1:
            raise HTTPException(status_code=409, detail="El hogar debe conservar al menos un propietario activo")
        # El propietario puede asignar/quitar administradores operativos, pero no crear otro propietario desde esta pantalla.
        if payload.role == MemberRole.owner and member.role != MemberRole.owner:
            raise HTTPException(status_code=400, detail="La transferencia de propietario queda protegida. Usá una acción específica más adelante.")
        member.role = payload.role
    session.add(member)
    session.commit()
    session.refresh(member)
    return member_to_read(member)


@router.patch("/members/{member_id}/active", response_model=MemberRead)
def set_member_active(
    member_id: int,
    payload: MemberActiveUpdate,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    ensure_owner(current_member)
    member = get_household_member(session, current_member.household_id, member_id)
    if member.id == current_member.id and not payload.is_active:
        raise HTTPException(status_code=409, detail="No podés desactivarte a vos mismo desde esta pantalla")

    if not payload.is_active:
        active_members = session.exec(
            select(Member).where(Member.household_id == current_member.household_id, Member.is_active == True)
        ).all()
        if len(active_members) <= 1:
            raise HTTPException(status_code=409, detail="El hogar debe conservar al menos un integrante activo")
        if member.role == MemberRole.owner:
            active_owners = [m for m in active_members if m.role == MemberRole.owner]
            if len(active_owners) <= 1:
                raise HTTPException(status_code=409, detail="El hogar debe conservar al menos un propietario activo")

    member.is_active = payload.is_active
    # No se borra historial: solo se oculta de los repartos futuros al estar inactivo.
    session.add(member)
    session.commit()
    session.refresh(member)
    return member_to_read(member)


@router.patch("/members/{member_id}/color", response_model=MemberRead)
def update_member_color(
    member_id: int,
    color: str,
    current_member: Member = Depends(get_current_member),
    session: Session = Depends(get_session),
):
    member = get_household_member(session, current_member.household_id, member_id)
    if current_member.role not in {MemberRole.owner, MemberRole.admin} and current_member.id != member.id:
        raise HTTPException(status_code=403, detail="Solo podés cambiar tu color o hacerlo como administrador")
    member.color = color.strip() or member.color
    session.add(member)
    session.commit()
    session.refresh(member)
    return member_to_read(member)
