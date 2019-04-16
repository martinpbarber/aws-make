import sys
import os

BASE_DIR = '.build/src'

for name in os.listdir(BASE_DIR):
    entry = BASE_DIR + '/' + name
    if os.path.isdir(entry):
        sys.path.append(entry)
