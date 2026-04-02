"""
Follow-up endpoint:
  POST /api/followup/submit  – update skill answers after follow-up questions
                               and return a refined ML prediction
"""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import QuestionnaireResult, User
from app.ml.predictor import predict, rule_based_risk
from app.routers.auth import _get_current_user
from app.schemas import FollowupSubmitRequest, FollowupSubmitResponse, PredictionResult

router = APIRouter(prefix="/api/followup", tags=["followup"])


@router.post("/submit", response_model=FollowupSubmitResponse)
def submit_followup(
    body: FollowupSubmitRequest,
    current_user: User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    result = db.query(QuestionnaireResult).filter(
        QuestionnaireResult.id == body.result_id,
        QuestionnaireResult.user_id == current_user.id,
    ).first()

    if result is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Assessment not found")

    # Merge follow-up answers with the original answers
    original_answers = {
        "response_to_name": result.response_to_name,
        "eye_contact": result.eye_contact,
        "social_smile": result.social_smile,
        "imitation": result.imitation,
        "discrimination": result.discrimination,
        "pointing_with_finger": result.pointing_with_finger,
        "facial_expressions": result.facial_expressions,
        "joint_attention": result.joint_attention,
        "play_skills": result.play_skills,
        "response_to_commands": result.response_to_commands,
    }

    updated_answers = {**original_answers, **{
        k: int(v) for k, v in body.followup_answers.items()
        if k in original_answers
    }}

    final_rule_risk, final_score = rule_based_risk(result.age_group, updated_answers)

    try:
        ml_risk, ml_confidence = predict(result.age_group, result.gender, updated_answers)
    except FileNotFoundError:
        ml_risk, ml_confidence = final_rule_risk, 1.0

    # Persist the refined result
    result.followup_answers = body.followup_answers
    result.final_score = final_score
    result.final_risk = final_rule_risk
    result.ml_risk = ml_risk
    result.ml_confidence = ml_confidence
    db.commit()

    return FollowupSubmitResponse(
        prediction=PredictionResult(
            risk=ml_risk,
            confidence=ml_confidence,
            score=final_score,
            rule_risk=final_rule_risk,
        )
    )
