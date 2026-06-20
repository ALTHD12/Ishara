import spacy

nlp = spacy.load("en_core_web_sm")

test_sentences = [
    "you hungry",
    "my name adithya",
    "i name adithya",
    "yesterday he car drive"
]

for s in test_sentences:
    print(f"Sentence: {s}")
    doc = nlp(s)
    for token in doc:
        print(f"  Token: {token.text} | POS: {token.pos_} | Dep: {token.dep_} | Head: {token.head.text} ({token.head.pos_})")
    print("-" * 50)
