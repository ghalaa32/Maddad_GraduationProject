"""
Profile endpoints:
  GET  /api/profile   - return the current user's profile
  PUT  /api/profile   - update child info
"""

from fastapi import APIRouter, Depends, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import ParentProfile, User
from app.routers.auth import _get_current_user
from app.schemas import ProfileResponse, ProfileUpdateRequest

router = APIRouter(prefix="/api/profile", tags=["profile"])


def _profile_response(user: User) -> ProfileResponse:
    profile = user.parent_profile
    return ProfileResponse(
        email=user.email,
        child_name=profile.child_name if profile else "",
        child_age=profile.child_age_group if profile else "",
        child_gender=profile.child_gender if profile else "",
        created_at=user.created_at,
    )


@router.get("", response_model=ProfileResponse)
def get_profile(current_user: User = Depends(_get_current_user)):
    return _profile_response(current_user)


@router.put("", response_model=ProfileResponse)
def update_profile(
    body: ProfileUpdateRequest,
    current_user: User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    # Ensure parent_profile row exists (created on registration, but guard anyway)
    if current_user.parent_profile is None:
        db.add(ParentProfile(user_id=current_user.id))
        db.flush()
        db.refresh(current_user)

    profile = current_user.parent_profile

    if body.child_name is not None:
        profile.child_name = body.child_name
    if body.child_age is not None:
        profile.child_age_group = body.child_age
    if body.child_gender is not None:
        profile.child_gender = body.child_gender
    if body.email is not None:
        current_user.email = body.email

    db.commit()
    db.refresh(current_user)

    return _profile_response(current_user)
