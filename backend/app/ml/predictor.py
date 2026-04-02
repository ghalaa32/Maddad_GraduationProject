"""
ML predictor: loads the trained model and exposes a predict() function.

The model file (model.pkl) must exist before the server starts.
Run the training script first:  python -m app.ml.train
"""

import pickle
from pathlib import Path
from typing import Tuple

import numpy as np

from app.ml.train import AGE_GROUP_ENCODING, RISK_NAMES, classify_risk_rule_based

_MODEL_PATH = Path(__file__).parent / "model.pkl"
_model = None


def _load_model():
    global _model
    if _model is None:
        if not _MODEL_PATH.exists():
            raise FileNotFoundError(
                f"ML model not found at {_MODEL_PATH}. "
                "Run `python -m app.ml.train` first."
            )
        with open(_MODEL_PATH, "rb") as f:
            _model = pickle.load(f)
    return _model


def predict(
    age_group: str,
    gender: str,
    answers: dict,
) -> Tuple[str, float]:
    """
    Predict the ASD risk level for a set of questionnaire answers.

    Parameters
    ----------
    age_group : '12-18' | '19-24' | '25-30' | '31-36'
    gender    : 'ذكر' | 'أنثى'
    answers   : dict mapping skill key → 0|1  (10 skills)

    Returns
    -------
    (risk_label, confidence)
      risk_label  : 'low' | 'medium' | 'high'
      confidence  : float in [0, 1] – max class probability
    """
    model = _load_model()

    skill_order = [
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

    age_enc = AGE_GROUP_ENCODING.get(age_group, 1)
    gender_enc = 0 if gender == "ذكر" else 1
    skill_values = [int(answers.get(k, 0)) for k in skill_order]

    features = np.array([[age_enc, gender_enc] + skill_values], dtype=np.int8)
    label_idx = int(model.predict(features)[0])
    proba = model.predict_proba(features)[0]
    confidence = float(proba[label_idx])

    return RISK_NAMES[label_idx], confidence


def rule_based_risk(age_group: str, answers: dict) -> Tuple[str, int]:
    """Return (risk, score) using the deterministic rule-based classifier."""
    score = sum(int(v) for v in answers.values())
    risk = classify_risk_rule_based(age_group, score)
    return risk, score
