import sys
import os

BASE_DIR = '.build/src'

for name in os.listdir(BASE_DIR):
    entry = BASE_DIR + '/' + name
    if os.path.isdir(entry):
        sys.path.append(entry)

#sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '.build/src/mpb')))
################################################################################
# Test the system
################################################################################
#$(TESTS_FILE): $(LAMBDA_SOURCES) build
#	@echo $(LAMBDA_SOURCES)
#	#$(ACTIVATE) && coverage run --omit='tests/*,$(VENV)/*,conftest.py' -m pytest -vv && coverage report -m
