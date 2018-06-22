# AWS Makefile
A Makefile that I use during development to package and deploy CloudFormation templates and SAM templates with associated code. The Makefile currently only supports code that is written in Python

## Repository Layout
The Makefile expects the following repository layout to function properly.

* Repository Root Directory
  * cloudformation
  * source
  * tests: Directory that contains Python unittest files
  * requirements.dev: Python requirements file for development modules
  * Makefile: The file that makes my life easier
  * bld
    * src
    * cfn

The "cloudformation" directory contains one or more CloudFormation/SAM templates.

The "source" directory is optional and can be structured in one of the following ways.
1. If the repository is only using CloudFormation templates the directory does not exist
1. If the repository is using SAM templates

The "tests" directory is optional and can be stru
