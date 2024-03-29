# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

#SHELL := /bin/sh
PY_VERSION := 3.8

export PYTHONUNBUFFERED := 1

# CloudFormation deployment variables
CFN_BUCKET_NAME ?= 
CFN_TEMPLATE_DIR := cfn-templates
CFN_OUTPUT_DIR := build/$(AWS_DEFAULT_REGION)
CFN_STACK_NAME ?= 
PROJECT_NAME := package-cfn

PYTHON := $(shell /usr/bin/which python$(PY_VERSION))

.DEFAULT_GOAL := package

clean:
	rm -fr $(CFN_OUTPUT_DIR)
	mkdir -p $(CFN_OUTPUT_DIR)
	cp $(CFN_TEMPLATE_DIR)/*.yaml ${CFN_OUTPUT_DIR}

delete:
	aws cloudformation delete-stack \
		--stack-name $(CFN_STACK_NAME)
	
build: clean

package: build 
		./package-cfn.sh $(CFN_BUCKET_NAME) $(AWS_DEFAULT_REGION)

cfn_nag_scan: 
	cfn_nag_scan --input-path ./${CFN_TEMPLATE_DIR}

zip:
	echo "Zipping the source code"
	rm -f ${PROJECT_NAME}.zip
	zip -r ${PROJECT_NAME}.zip . -x "*.pdf" -x "*.git*" -x "*.DS_Store*" -x "*.vscode*" -x "/build/*"

cfn_nag_scan: 
	cfn_nag_scan --input-path ./cfn-templates


