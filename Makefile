# Directory definitions
#CFN_DIR := cloudformation
#SRC_DIR := source
#LAMBDA_SRC_DIR := $(SRC_DIR)/lambda
#VENV_DIR := .venv
#BLD_DIR := .build
#BLD_CFN_DIR := $(BLD_DIR)/cfn
#BLD_SRC_DIR := $(BLD_DIR)/src
#BLD_LAMBDA_SRC_DIR := $(BLD_SRC_DIR)/lambda
#DEPLOY_DIR := .deploy

SOURCE_DIR := source
LAMBDA_SOURCE_DIR := $(SOURCE_DIR)/lambda

BUILD_DIR := .build
BUILD_SRC_DIR := $(BUILD_DIR)/src

#LAMBDA_SOURCES := $(wildcard $(LAMBDA_SOURCE_DIR)/*.py)
LAMBDA_DIRECTORIES := $(shell find $(LAMBDA_SOURCE_DIR) -type d -path '$(LAMBDA_SOURCE_DIR)/*')
LAMBDA_SOURCES := $(shell find $(LAMBDA_SOURCE_DIR) -type f -name '*.py')
LAMBDA_REQUIREMENTS := $(shell find $(LAMBDA_SOURCE_DIR) -type f -name 'requirements.txt')

BUILD_LAMBDA_DIRECTORIES := $(subst $(LAMBDA_SOURCE_DIR),$(BUILD_SRC_DIR),$(LAMBDA_DIRECTORIES))
BUILD_LAMBDA_SOURCES := $(subst $(LAMBDA_SOURCE_DIR),$(BUILD_SRC_DIR),$(LAMBDA_SOURCES))
BUILD_LAMBDA_REQUIREMENTS := $(subst $(LAMBDA_SOURCE_DIR),$(BUILD_SRC_DIR),$(LAMBDA_REQUIREMENTS))

# S3 Bucket information
# Bucket name from environment, prefix from repo name
BUCKET := ${BUCKET}
PREFIX ?= $(shell basename `pwd`)

# Set prefix for unique deployments, default is the user name
STACK_PREFIX ?= $(shell whoami | cut -d- -f1)

# AWS CLI Command
AWS := $(shell which aws)

# AWS Region
AWS_REGION ?= us-east-1


# Python virtual environment
VENV := .venv

# Python command
PYTHON ?= python36

# Python Activate Command
ACTIVATE := . $(VENV)/bin/activate

# Build Requirements
REQUIREMENTS := requirements.txt

# Coverage temp file
COVERAGE := .coverage

# Get rid of default suffixes, helpful when debugging
.SUFFIXES:

	# List of stacks to deploy, order is important
	STACK_LIST := $(DEPLOY_DIR)/$(ALIST_STACK)

	# List of stacks to delete, order is important
	DELETE_STACK_LIST := $(DEPLOY_DIR)/$(ALIST_STACK)

################################################################################
# Pattern Rules
################################################################################
# Build directory and install items in requirements.txt
$(BUILD_SRC_DIR)/%: $(LAMBDA_SOURCE_DIR)/%/requirements.txt
	mkdir -p $@
	$(ACTIVATE) && pip install -r $< -t $@
	rm -rf $@/*.dist-info $@/*.egg-info

# Copy source code to build area and then lint
$(BUILD_SRC_DIR)/%.py: $(LAMBDA_SOURCE_DIR)/%.py
	cp $< $@
	$(ACTIVATE) && pylint $@

# Pattern rule that packages CloudFormation templates
# Lint and validate CloudFormation templates
# Then package SAM templates or just copy standard Cloudformation templates
# TODO: This needs to be a little cleaner, permission issues don't cause failure
$(BUILD_CFN_DIR)/%.yml: $(CFN_DIR)/%.yml
	$(ACTIVATE) && yamllint $<
	aws --region $(AWS_REGION) cloudformation validate-template --template-body file://$<
	aws cloudformation package --region $(AWS_REGION) --template-file $< --output-template-file $@ --s3-bucket $(BUCKET) --s3-prefix $(PREFIX)

#	$(ACTIVATE) && yamllint $<
#	$(AWS) --region $(AWS_REGION) cloudformation validate-template --template-body file://$<
#	grep -q '^Transform:\s\+AWS::Serverless-[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\}\s*$$' $< && \
#	aws cloudformation package --region $(AWS_REGION) --template-file $< --output-template-file $@ --s3-bucket $(BUCKET) --s3-prefix $(PREFIX) || \
#	cp $< $@
##aws cloudformation package --region $(AWS_REGION) --template-file $< --output-template-file $@ --s3-bucket $(BUCKET) --s3-prefix $(PREFIX)

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
all: build $(COVERAGE)

################################################################################
# Build the system
################################################################################
.PHONY: build
build: $(BUILD_LAMBDA_DIRECTORIES) $(BUILD_LAMBDA_SOURCES)

$(BUILD_LAMBDA_DIRECTORIES): | $(VENV)


# Build directory
$(BUILD_DIR):
	mkdir $(BUILD_DIR)
$(BUILD_CFN_DIR): | $(BUILD_DIR)
	mkdir $(_CFN_DIR)
$(BUILD_SRC_DIR): | $(BUILD_DIR)
	mkdir $(BUILD_SRC_DIR)

# Python virtual environment
$(VENV): $(REQUIREMENTS)
	$(PYTHON) -m venv $(VENV)
	$(ACTIVATE) && pip install --upgrade pip
	$(ACTIVATE) && pip install -r $(REQUIREMENTS)
	touch $@

################################################################################
# Test the system
#
# TODO: This will run on second falure of pylint, fix dependancy
################################################################################
$(COVERAGE): $(BUILD_LAMBDA_SOURCES)
	$(ACTIVATE) && coverage run --omit='tests/*,$(VENV)/*,conftest.py' -m pytest -vv && coverage report -m

################################################################################
# Deploy the system
################################################################################
.PHONY: deploy
deploy: build $(STACK_LIST)

$(STACK_LIST): | $(DEPLOY_DIR)


# Deploy directory
$(DEPLOY_DIR):
	mkdir $(DEPLOY_DIR)

# Remove stacks, evaluate now so only deployed stack are deleted
.PHONY: destroy
destroy:
	$(eval STACKS = $(shell for STACK in $(DELETE_STACK_LIST); do ls $$STACK 2>/dev/null | sed -e 's#$(BLD_CFN_DIR)/##' -e 's/.stack//';done))
	$(foreach STACK, $(STACKS), $(AWS) cloudformation delete-stack --region $(AWS_REGION) --stack-name $(STACK_PREFIX)-$(STACK) && $(AWS) cloudformation wait stack-delete-complete --region $(AWS_REGION) --stack-name $(STACK_PREFIX)-$(STACK) && rm $(BLD_CFN_DIR)/$(STACK).stack;)


################################################################################
# Clean the workspace
################################################################################
.PHONY: clean
clean: clean-build clean-venv clean-python clean-test

# Remove the build files
.PHONY: clean-build
clean-build:
	rm -rf $(BUILD_DIR)

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
