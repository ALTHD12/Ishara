import re

with open('lib/screens/english_to_isl_screen.dart', 'r') as f:
    lines = f.readlines()

children_start = -1
for i, line in enumerate(lines):
    if line.strip() == 'children: [':
        children_start = i
        break

if children_start == -1:
    print("Error: Could not find 'children: ['")
    exit(1)

# The children start at children_start + 1.
# Block A (Input, Translate, Chips) is from children_start + 1 up to the start of "Gloss sequence pill"
# Let's find "Gloss sequence pill"
gloss_pill_start = -1
for i in range(children_start + 1, len(lines)):
    if 'Gloss sequence pill' in lines[i]:
        gloss_pill_start = i - 1 # The line with the comment bar above it
        break

# Let's find "Natural Language Output Card"
output_card_start = -1
for i in range(gloss_pill_start, len(lines)):
    if 'Natural Language Output Card' in lines[i]:
        output_card_start = i
        break

# Block A is from children_start + 1 to gloss_pill_start
block_a = lines[children_start + 1 : gloss_pill_start]

# Block B is from gloss_pill_start to output_card_start
block_b = lines[gloss_pill_start : output_card_start]

# We want the order to be: children: [ \n Block B \n Block A \n Output Card
new_lines = lines[:children_start + 1] + block_b + block_a + lines[output_card_start:]

with open('lib/screens/english_to_isl_screen.dart', 'w') as f:
    f.writelines(new_lines)

print("Reordered successfully!")
