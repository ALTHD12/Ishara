from fastapi import APIRouter
from pydantic import BaseModel
from nlp.spacy_model import ISLTranslator

router = APIRouter()

class TextRequest(BaseModel):
    text: str

@router.post("/english-to-isl")
async def english_to_isl(request: TextRequest):
    return ISLTranslator.english_to_isl_gloss(request.text)
