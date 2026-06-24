from fastapi import APIRouter
from pydantic import BaseModel
from nlp.spacy_model import ISLTranslator

router = APIRouter()

class TextRequest(BaseModel):
    text: str

@router.post("/english-to-isl")
async def english_to_isl(request: TextRequest):
    return ISLTranslator.english_to_isl_gloss(request.text)

@router.post("/isl-to-english")
async def isl_to_english(request: TextRequest):
    return ISLTranslator.isl_gloss_to_english(request.text)
