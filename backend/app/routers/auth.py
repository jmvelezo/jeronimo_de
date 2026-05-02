from secrets import token_hex
from typing import Annotated
import jwt
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlmodel import Session, select
from ..database import get_session
from ..models import Household, Member, MemberRole
from ..schemas import HouseholdCreate, HouseholdRead, MemberRead, AuthLogin, TokenRead
from ..services.security import create_access_token, decode_access_token, hash_pin, verify_pin

router = APIRouter(prefix="/auth", tags=["auth"])
security = HTTPBearer()


def member_to_read(member: Member) -> MemberRead:
    return MemberRead(
        id=member.id or 0,
        household_id=member.household_id,
        name=member.name,
        color=member.color,
        role=member.role,
        is_active=member.is_active,
    )


def household_to_read(household: Household) -> HouseholdRead:
    return HouseholdRead(id=household.id or 0, name=household.name, invite_code=household.invite_code)


def get_current_member(
    credentials: Annotated[HTTPAuthorizationCredentials, Depends(security)],
    session: Annotated[Session, Depends(get_session)],
) -> Member:
    try:
        payload = decode_access_token(credentials.credentials)
        member_id = int(payload.get("sub"))
        household_id = int(payload.get("household_id"))
    except (jwt.InvalidTokenError, TypeError, ValueError):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Sesión inválida o vencida")

    member = session.get(Member, member_id)
    if not member or member.household_id != household_id or not member.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Usuario no encontrado")
    return member


@router.post("/register-household", response_model=TokenRead)
def register_household(payload: HouseholdCreate, session: Session = Depends(get_session)) -> TokenRead:
    if len(payload.members) < 1:
        raise HTTPException(status_code=400, detail="Debe existir al menos un integrante")

    invite_code = (payload.invite_code or token_hex(3)).strip().upper().replace(" ", "-")
    existing = session.exec(select(Household).where(Household.invite_code == invite_code)).first()
    if existing:
        raise HTTPException(status_code=409, detail="Ese código de hogar ya existe")

    household = Household(name=payload.name.strip(), invite_code=invite_code)
    session.add(household)
    session.commit()
    session.refresh(household)

    first_member: Member | None = None
    for index, member_payload in enumerate(payload.members):
        role = member_payload.role
        if index == 0:
            role = MemberRole.owner
        member = Member(
            household_id=household.id or 0,
            name=member_payload.name.strip(),
            color=member_payload.color,
            role=role,
            pin_hash=hash_pin(member_payload.pin),
        )
        session.add(member)
        session.commit()
        session.refresh(member)
        if first_member is None:
            first_member = member

    assert first_member is not None
    token = create_access_token(member_id=first_member.id or 0, household_id=household.id or 0)
    return TokenRead(access_token=token, household=household_to_read(household), member=member_to_read(first_member))


@router.post("/login", response_model=TokenRead)
def login(payload: AuthLogin, session: Session = Depends(get_session)) -> TokenRead:
    household = session.exec(
        select(Household).where(Household.invite_code == payload.household_code.strip().upper())
    ).first()
    if not household:
        raise HTTPException(status_code=401, detail="Código de hogar incorrecto")

    members = session.exec(select(Member).where(Member.household_id == household.id, Member.is_active == True)).all()
    member = next((m for m in members if m.name.strip().lower() == payload.member_name.strip().lower()), None)
    if not member or not verify_pin(payload.pin, member.pin_hash):
        raise HTTPException(status_code=401, detail="Nombre o PIN incorrecto")

    token = create_access_token(member_id=member.id or 0, household_id=household.id or 0)
    return TokenRead(access_token=token, household=household_to_read(household), member=member_to_read(member))


@router.get("/me", response_model=MemberRead)
def me(current_member: Member = Depends(get_current_member)) -> MemberRead:
    return member_to_read(current_member)
