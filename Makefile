################################################################################
# CloudFormation Templates
################################################################################
# Order is important so templates get deployed properly
TEMPLATE_LIST := cfn-template.yml sam-template.yml

################################################################################
# Directory Definitions
################################################################################
CFN_DIR := cloudformation
SRC_DIR := source
LAMBDA_SRC_DIR := $(SRC_DIR)/lambda
BLD_DIR := .build
BLD_CFN_DIR := $(BLD_DIR)/cfn
BLD_SRC_DIR := $(BLD_DIR)/src
TST_DIR := tests
DEPLOY_DIR := .deploy

################################################################################
# Lambda directories, source code and requirements
################################################################################
LAMBDA_DIRECTORIES := $(shell find $(LAMBDA_SRC_DIR) -type d -path '$(LAMBDA_SRC_DIR)/*')
LAMBDA_SOURCES := $(shell find $(LAMBDA_SRC_DIR) -type f -name '*.py')
LAMBDA_REQUIREMENTS := $(shell find $(LAMBDA_SRC_DIR) -type f -name 'requirements.txt')
BUILD_LAMBDA_DIRECTORIES := $(subst $(LAMBDA_SRC_DIR),$(BLD_SRC_DIR),$(LAMBDA_DIRECTORIES))
BUILD_LAMBDA_SOURCES := $(subst $(LAMBDA_SRC_DIR),$(BLD_SRC_DIR),$(LAMBDA_SOURCES))
BUILD_LAMBDA_REQUIREMENTS := $(subst $(LAMBDA_SRC_DIR),$(BLD_SRC_DIR),$(LAMBDA_REQUIREMENTS))

################################################################################
# Tests
################################################################################
TESTS := $(wildcard $(TST_DIR)/*.py)

################################################################################
# Stack Definitions
################################################################################
# Built Cloudformation Templates
BLD_TEMPLATES := $(patsubst %, $(BLD_CFN_DIR)/%,$(TEMPLATE_LIST))
# List of stacks to deploy, order is important
STACKS := $(patsubst %.yml, $(DEPLOY_DIR)/%.stack,$(TEMPLATE_LIST))
# List of stacks to delete, order is important
STACKS_REVERSED := $(shell echo $(STACKS) | awk '{for(i=NF; i>=1; i--) printf "%s ", $$i}')
# Set prefix for unique deployments, default is the user name
STACK_PREFIX ?= $(shell whoami | cut -d- -f1)

################################################################################
# AWS Settings
################################################################################
# S3 Bucket Info - Name from environment, prefix from repo name
BUCKET := ${BUCKET}
PREFIX ?= $(shell basename `pwd`)
# AWS CLI Command
AWS := $(shell which aws)
# AWS Region
AWS_REGION ?= us-east-1

################################################################################
# Python Settings
################################################################################
# Python command
PYTHON ?= python3
# Python virtual environment
VENV := .venv
# Python Activate Command
ACTIVATE := . $(VENV)/bin/activate
# Build Requirements
REQUIREMENTS := requirements.txt

################################################################################
# Testing Settings
################################################################################
# Coverage temp file
COVERAGE := .coverage
# Coverage commands
COVERAGE_RUN_CMD = coverage run --omit='tests/*,$(VENV)/*,conftest.py'
COVERAGE_REPORT_CMD = coverage report -m
# Pytest command
PYTEST_CMD = pytest -vv --disable-pytest-warning -s

################################################################################
# Make Settings
################################################################################
# Get rid of default suffixes, helpful when debugging
.SUFFIXES:

################################################################################
# Pattern Rules
################################################################################
# Build directory and install items in requirements.txt
$(BLD_SRC_DIR)/%: $(LAMBDA_SRC_DIR)/%/requirements.txt
	mkdir -p $@
	$(ACTIVATE) && pip install -r $< -t $@
	rm -rf $@/*.dist-info $@/*.egg-info
	touch $@

# Copy source code to build area and then lint
$(BLD_SRC_DIR)/%.py: $(LAMBDA_SRC_DIR)/%.py
	$(ACTIVATE) && pylint $<
	cp $< $@

# Pattern rule that packages CloudFormation templates
# Lint and validate CloudFormation templates
# Packaging works for both SAM and standard Cloudformation templates
$(BLD_CFN_DIR)/%.yml: $(CFN_DIR)/%.yml
	$(ACTIVATE) && yamllint $<
	aws --region $(AWS_REGION) cloudformation validate-template --template-body file://$<
	aws cloudformation package --region $(AWS_REGION) --template-file $< --output-template-file $@ --s3-bucket $(BUCKET) --s3-prefix $(PREFIX)

# Deploy CloudFormation templates
# A marker file is created if deployment is successful
# The stack is deleted if creation fails, but preserved if an update fails
$(DEPLOY_DIR)/%.stack: $(BLD_CFN_DIR)/%.yml
	$(eval STACK_NAME = $(STACK_PREFIX)-$(*F))
	$(eval CONTINUE = $(shell test -f $@ || echo '-'))
	$(CONTINUE)aws cloudformation deploy --no-fail-on-empty-changeset --region $(AWS_REGION) --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM --template-file $< --stack-name $(STACK_NAME) && touch $@
	@test -f $@ || (aws cloudformation --region $(AWS_REGION) describe-stack-events --stack-name $(STACK_NAME) --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`].[LogicalResourceId,ResourceType,ResourceStatus,ResourceStatusReason]' --output table; aws cloudformation --region $(AWS_REGION) delete-stack --stack-name $(STACK_NAME); false)
	@test -f $@ && aws cloudformation --region $(AWS_REGION) describe-stack-resources --stack-name $(STACK_NAME) > $@


################################################################################
# Make everything
################################################################################
.PHONY: all
all: build test

################################################################################
# Build the system
# TODO: ALL templates currently depend on ALL sources/requirements
#	This needs to be updated so templates depend on included sources/requirements
################################################################################
.PHONY: build
build: $(BUILD_LAMBDA_DIRECTORIES) $(BUILD_LAMBDA_SOURCES) $(BLD_TEMPLATES)

$(BLD_TEMPLATES): | $(VENV) $(BLD_CFN_DIR)
$(BLD_TEMPLATES): $(LAMBDA_SOURCES) $(LAMBDA_REQUIREMENTS)
$(BUILD_LAMBDA_DIRECTORIES): | $(VENV)

# Build directory
$(BLD_DIR):
	mkdir $(BLD_DIR)
$(BLD_CFN_DIR): | $(BLD_DIR)
	mkdir $(BLD_CFN_DIR)
$(BLD_SRC_DIR): | $(BLD_DIR)
	mkdir $(BLD_SRC_DIR)

# Python virtual environment
$(VENV): $(REQUIREMENTS)
	$(PYTHON) -m venv $(VENV)
	$(ACTIVATE) && pip install --upgrade pip
	$(ACTIVATE) && pip install -r $(REQUIREMENTS)
	touch $@

################################################################################
# Test the system
################################################################################
.PHONY: test
test: $(COVERAGE)

$(COVERAGE): $(BUILD_LAMBDA_SOURCES) $(LAMBDA_REQUIREMENTS) $(TESTS)
	$(ACTIVATE) && $(COVERAGE_RUN_CMD) -m $(PYTEST_CMD) && $(COVERAGE_REPORT_CMD)
	@find . -type d -name __pycache__ -exec rm -rf {} \+

################################################################################
# Deploy the system
################################################################################
.PHONY: deploy
deploy: build test $(STACKS)

$(STACKS): $(BLD_TEMPLATES) $(BUILD_LAMBDA_DIRECTORIES) | $(DEPLOY_DIR)

# Deploy directory
$(DEPLOY_DIR):
	mkdir $(DEPLOY_DIR)

################################################################################
# Destroy the system
################################################################################
.PHONY: destroy
destroy: destroy-stacks destroy-s3-objects

# Remove stacks, evaluate now so only deployed stack are deleted
.PHONY: destroy-stacks
destroy-stacks:
	$(eval STACKS_TO_DELETE = $(shell for STACK in $(STACKS_REVERSED); do ls $$STACK 2>/dev/null | sed -e 's#$(DEPLOY_DIR)/##' -e 's/.stack//';done))
	$(foreach STACK, $(STACKS_TO_DELETE), $(AWS) cloudformation delete-stack --region $(AWS_REGION) --stack-name $(STACK_PREFIX)-$(STACK) && $(AWS) cloudformation wait stack-delete-complete --region $(AWS_REGION) --stack-name $(STACK_PREFIX)-$(STACK) && rm $(DEPLOY_DIR)/$(STACK).stack;)
	rm -rf $(DEPLOY_DIR)

# Remove deployed code from our bucket prefix
.PHONY: destroy-s3-objects
destroy-s3-objects:
	aws s3 rm --region $(AWS_REGION) --recursive s3://$(BUCKET) --exclude '*' --include '$(PREFIX)/*'

################################################################################
# Clean the workspace
################################################################################
.PHONY: clean
clean: clean-build clean-venv clean-python clean-test

# Remove the build files
.PHONY: clean-build
clean-build:
	rm -rf $(BLD_DIR)

# Remove the Python virtual environment
.PHONY: clean-venv
clean-venv:
	rm -rf $(VENV)

# Remove the Python cruft
.PHONY: clean-python
clean-python:
	find . -type d -name __pycache__ -exec rm -rf {} \+
	find . -type f -name "*.py[c|o]" -exec rm -f {} \+

# Remove the testing files
.PHONY: clean-test
clean-test:
	rm -f $(COVERAGE)
	rm -rf .pytest_cache
