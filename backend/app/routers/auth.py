"""
Authentication endpoints:
  POST /api/auth/register
  POST /api/auth/login
  POST /api/auth/logout
"""

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.orm import Session

from app import auth as auth_utils
from app.database import get_db
from app.models import ParentProfile, Session as DBSession, User
from app.schemas import LoginRequest, RegisterRequest, TokenResponse

router = APIRouter(prefix="/api/auth", tags=["auth"])


def _get_current_user(request: Request, db: Session = Depends(get_db)) -> User:
    """Dependency: verify Bearer token and return the authenticated User."""
    authorization = request.headers.get("Authorization", "")
    if not authorization.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    token = authorization.split(" ", 1)[1]
    payload = auth_utils.decode_access_token(token)
    if payload is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid or expired token")
    user_id = payload.get("sub")
    if user_id is None:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid token payload")
    user = db.query(User).filter(User.id == int(user_id)).first()
    if user is None or not user.is_active:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user


def _build_token_response(user: User) -> TokenResponse:
    """Build a TokenResponse from a User + its ParentProfile."""
    profile = user.parent_profile
    token = auth_utils.create_access_token({"sub": str(user.id)})
    return TokenResponse(
        access_token=token,
        child_name=profile.child_name if profile else "",
        child_age=profile.child_age_group if profile else "",
        child_gender=profile.child_gender if profile else "",
        email=user.email,
    )


@router.post("/register", response_model=TokenResponse, status_code=status.HTTP_201_CREATED)
def register(body: RegisterRequest, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.email == body.email).first()
    if existing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="البريد الإلكتروني مستخدم بالفعل",
        )

    user = User(
        user_type="parent",
        email=body.email,
        password_hash=auth_utils.hash_password(body.password),
        first_name="",
        last_name="",
        is_active=True,
    )
    db.add(user)
    db.flush()  # populate user.id before creating the profile

    profile = ParentProfile(
        user_id=user.id,
        child_name=body.child_name,
        child_age_group=body.child_age,
        child_gender=body.child_gender,
    )
    db.add(profile)
    db.commit()
    db.refresh(user)

    return _build_token_response(user)


@router.post("/login", response_model=TokenResponse)
def login(body: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.email == body.email).first()
    if user is None or not auth_utils.verify_password(body.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="البريد الإلكتروني أو كلمة المرور غير صحيحة",
        )
    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="الحساب معطّل")

    return _build_token_response(user)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout():
    # Tokens are stateless JWTs; logout is handled client-side by deleting the token.
    return None
