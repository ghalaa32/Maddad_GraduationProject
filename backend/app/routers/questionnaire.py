"""
Questionnaire endpoints:
  POST /api/questionnaire/submit   – store answers and return ML prediction
  GET  /api/questionnaire/history  – list past assessments for the current user
"""

from typing import List

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import QuestionnaireResult, User
from app.ml.predictor import predict, rule_based_risk
from app.routers.auth import _get_current_user
from app.schemas import (
    HistoryItem,
    PredictionResult,
    QuestionnaireSubmitRequest,
    QuestionnaireSubmitResponse,
)

SKILL_KEYS = [
    "response_to_name",
    "eye_contact",
    "social_smile",
    "imitation",
    "discrimination",
    "pointing_with_finger",
    "facial_expressions",
    "joint_attention",
    "play_skills",
    "response_to_commands",
]

router = APIRouter(prefix="/api/questionnaire", tags=["questionnaire"])


@router.post("/submit", response_model=QuestionnaireSubmitResponse, status_code=status.HTTP_201_CREATED)
def submit_questionnaire(
    body: QuestionnaireSubmitRequest,
    current_user: User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    answers_dict = body.answers.model_dump()

    # Rule-based classification (mirrors the JS classifyRisk function)
    rule_risk, score = rule_based_risk(body.age_group, answers_dict)

    # ML prediction
    try:
        ml_risk, ml_confidence = predict(body.age_group, body.gender, answers_dict)
    except FileNotFoundError:
        # If the model hasn't been trained yet, fall back to the rule-based result
        ml_risk, ml_confidence = rule_risk, 1.0

    failed_skills = [k for k, v in answers_dict.items() if v == 1]
    followup_needed = rule_risk in ("medium", "high")

    result = QuestionnaireResult(
        user_id=current_user.id,
        age_group=body.age_group,
        gender=body.gender,
        **answers_dict,
        initial_score=score,
        initial_risk=rule_risk,
        ml_risk=ml_risk,
        ml_confidence=ml_confidence,
    )
    db.add(result)
    db.commit()
    db.refresh(result)

    return QuestionnaireSubmitResponse(
        result_id=result.id,
        prediction=PredictionResult(
            risk=ml_risk,
            confidence=ml_confidence,
            score=score,
            rule_risk=rule_risk,
        ),
        failed_skills=failed_skills,
        followup_needed=followup_needed,
    )


@router.get("/history", response_model=List[HistoryItem])
def get_history(
    current_user: User = Depends(_get_current_user),
    db: Session = Depends(get_db),
):
    results = (
        db.query(QuestionnaireResult)
        .filter(QuestionnaireResult.user_id == current_user.id)
        .order_by(QuestionnaireResult.created_at.desc())
        .all()
    )

    return [
        HistoryItem(
            id=r.id,
            date=r.created_at,
            age_group=r.age_group,
            initial_risk=r.initial_risk,
            final_risk=r.final_risk,
            ml_risk=r.ml_risk,
            ml_confidence=r.ml_confidence,
            score=r.final_score if r.final_score is not None else r.initial_score,
        )
        for r in results
    ]
