import spacy

nlp = spacy.load("en_core_web_sm")

WH_WORDS = {'what', 'where', 'when', 'who', 'why', 'how', 'which'}
TIME_WORDS = {'tomorrow', 'yesterday', 'today', 'now', 'later', 'soon', 'morning', 'evening'}

class ISLTranslator:
    @staticmethod
    def english_to_isl_gloss(text: str):
        text = text.strip().lower()
        doc = nlp(text)
        
        time_tokens = []
        subject_tokens = []
        verb_tokens = []
        object_tokens = []
        wh_tokens = []
        negation_tokens = []
        other_tokens = []
        
        is_q = "?" in text
        
        for token in doc:
            w = token.text
            if token.is_punct: continue
            if token.lemma_ == "be": continue # drop is, am, are
            if token.pos_ == "DET": continue # drop the, a, an
            
            upper_w = w.upper()
            if w in TIME_WORDS:
                time_tokens.append(upper_w)
            elif w in WH_WORDS:
                wh_tokens.append(upper_w)
            elif w in ["not", "never", "no"]:
                negation_tokens.append(upper_w)
            elif "subj" in token.dep_:
                subject_tokens.append(upper_w)
            elif "obj" in token.dep_:
                object_tokens.append(upper_w)
            elif token.pos_ == "VERB":
                verb_tokens.append(token.lemma_.upper()) # Convert verb to root
            elif token.pos_ == "PRON" and not subject_tokens: # Fallback
                subject_tokens.append(upper_w)
            else:
                other_tokens.append(upper_w)
                
        # ISL Structure: TIME + SUBJECT + OBJECT + VERB + OTHER + NEGATION + WH
        isl_gloss = []
        isl_gloss.extend(time_tokens)
        isl_gloss.extend(subject_tokens)
        isl_gloss.extend(object_tokens)
        isl_gloss.extend(verb_tokens)
        isl_gloss.extend(other_tokens)
        isl_gloss.extend(negation_tokens)
        isl_gloss.extend(wh_tokens)
        
        if is_q and not wh_tokens:
            isl_gloss.append("Q")
            
        # For UI display tokens
        display_tokens = []
        for token in isl_gloss:
            role = "OTHER"
            if token in time_tokens: role = "TIME"
            elif token in subject_tokens: role = "SUBJECT"
            elif token in object_tokens: role = "OBJECT"
            elif token in verb_tokens: role = "VERB"
            elif token in wh_tokens: role = "WH-WORD"
            elif token in negation_tokens: role = "NEGATION"
            elif token == "Q": role = "YNQ-MARKER"
            display_tokens.append({"gloss": token, "role": role})

        return {
            "output": " ".join(isl_gloss),
            "tokens": display_tokens,
            "note": "Processed using spaCy NLP backend (SOV Order + Time Hoisting)"
        }
