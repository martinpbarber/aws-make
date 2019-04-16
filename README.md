# AWS Makefile
A Makefile that I use during development to package and deploy CloudFormation templates and SAM templates with associated code. The Makefile currently only supports code written in Python

## Repository Layout
The Makefile requires the following repository layout.

  * cloudformation: Directory for CloudFormation/SAM templates
  * source/lambda: Directories for Python source
  * tests: Directory for test files (coverage/pytest)
  * requirements.dev: Python requirements file for development
  * .yamllint: Python yamllint configuration file
  * conftest.py: Python pytest configuration file

The following directories are created by the Makefile during the development process.

  * .build: Directory that contains build artifacts
    * cfn: Directory for packaged CloudFormation/SAM templates
    * src: Directory for lambda packaged python source and modules
  * .deploy: directory that contains stack deployment file
  * .venv: Python virtual environment

## Makefile Usage

The Makefile requires the following environment variable to be set.

  * BUCKET: S3 bucket used to hold lambda build artifacts

The Makefile supports the following commands.

  * all: Default target, runs build and tests
  * build: Build templates and source, includes linting/validation
  * test: Execute test files
  * deploy: Create CloudFormation stacks
  * destroy: Delete CloudFormation stacks
  * clean: Delete build and test artifacts
