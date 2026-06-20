import sys
from main import english_to_isl_semantic_detailed, isl_to_english_detailed
from sentence_db import DATABASE, clean_sentence

print("==============================================")
print("Running 50 Standard Database Sentences Tests")
print("==============================================")

success_count = 0
failed_count = 0

for item in DATABASE:
    eng_input = item["english"]
    expected_isl = item["isl"]
    
    # Test English -> ISL
    try:
        res_isl = english_to_isl_semantic_detailed(eng_input)
        cleaned_res = clean_sentence(res_isl["result"])
        cleaned_exp = clean_sentence(expected_isl)
        
        if cleaned_res == cleaned_exp:
            success_count += 1
        else:
            failed_count += 1
            print(f"FAILED (Eng -> ISL) Row {item['id']}: '{eng_input}'")
            print(f"  Expected: '{expected_isl}'")
            print(f"  Got:      '{res_isl['result']}'")
    except Exception as e:
        failed_count += 1
        print(f"ERROR (Eng -> ISL) Row {item['id']}: '{eng_input}' -> {e}")
        
    # Test ISL -> English
    try:
        res_eng = isl_to_english_detailed(expected_isl)
        cleaned_res = clean_sentence(res_eng["result"])
        cleaned_exp = clean_sentence(eng_input)
        
        if cleaned_res == cleaned_exp:
            success_count += 1
        else:
            failed_count += 1
            print(f"FAILED (ISL -> Eng) Row {item['id']}: '{expected_isl}'")
            print(f"  Expected: '{eng_input}'")
            print(f"  Got:      '{res_eng['result']}'")
    except Exception as e:
        failed_count += 1
        print(f"ERROR (ISL -> Eng) Row {item['id']}: '{expected_isl}' -> {e}")

print(f"\nDatabase Tests Completed: {success_count} passed, {failed_count} failed.")

print("\n==============================================")
print("Running Custom/Dynamic Parser Tests")
print("==============================================")

custom_test_cases = [
    # Custom ISL -> English
    ("I SCHOOL GO", "I go to school."),
    ("TOMORROW I SCHOOL GO", "I will go to school tomorrow."),
    ("COUNTER TICKET WHERE", "Where is the ticket counter?"),
    ("YOU ME HELP", "You help me."),
    # Custom English -> ISL
    ("Where is the ticket counter?", "COUNTER TICKET WHERE"),
    ("Can you help me?", "YOU ME HELP"),
]

custom_success = 0
custom_failed = 0

for sentence, expected in custom_test_cases:
    # Determine mode
    is_isl_input = sentence.isupper()
    try:
        if is_isl_input:
            res = isl_to_english_detailed(sentence)
            res_str = res["result"]
        else:
            res = english_to_isl_semantic_detailed(sentence)
            res_str = res["result"]
            
        cleaned_res = clean_sentence(res_str)
        cleaned_exp = clean_sentence(expected)
        
        if cleaned_res == cleaned_exp:
            custom_success += 1
            print(f"PASS: '{sentence}' -> '{res_str}'")
        else:
            custom_failed += 1
            print(f"FAIL: '{sentence}'")
            print(f"  Expected: '{expected}'")
            print(f"  Got:      '{res_str}'")
    except Exception as e:
        custom_failed += 1
        print(f"ERROR: '{sentence}' -> {e}")

print(f"\nCustom Tests Completed: {custom_success} passed, {custom_failed} failed.")

if failed_count > 0 or custom_failed > 0:
    sys.exit(1)
else:
    sys.exit(0)
