import sys
import os
import re

directory = sys.argv[1]
pattern = sys.argv[2] + r"\.(.*?)\.json"
for filename in os.listdir(directory):
    if re.match(pattern, filename):
        middle_word = re.search(pattern, filename).group(1)
        print(middle_word)
