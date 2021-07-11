#!/bin/bash

# Copyright 2019 Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0

set -e

# This script will package the CloudFormation in ${CFN_TEMPLATE_DIR} directory and upload it 
# to Amazon S3 in preparation for deployment using the AWS CloudFromation service.  
# 
# This script exists because Service Catalog products, when using relative references to cloudformation templates are 
# not properly packaged by the AWS cli. Also the full stack, due to 2 levels of Service Catalog deployment will not 
# always package properly using the AWS cli.

# This script treats the templates as source code and packages them, putting the results into a 'build' subdirectory.

# This script assumes a Linux or MacOSX environment and relies on the following software packages being installed:
# . - AWS Command Line Interface (CLI)
# . - sed
# . - Python 3 / pip3
# . - zip

# PLEASE NOTE this script will store all resources to an Amazon S3 bucket s3://${CFN_BUCKET_NAME}/${PROJECT_NAME}
CFN_BUCKET_NAME=$1
DEPLOYMENT_REGION=$2
PROJECT_NAME="package-cfn"
CFN_TEMPLATE_DIR="cfn-templates"
CFN_OUTPUT_DIR="build/${DEPLOYMENT_REGION}"

# files that need to be scrubbed with sed to replace < S3 BUCKET LOCATION > with an actual S3 bucket name
SELF_PACKAGE_LIST="nested-1.yaml"

# files to be packaged using `aws cloudformation package`
AWS_PACKAGE_LIST="main.yaml"

# files that won't be uploaded by `aws cloudformation package` - they must be uploaded separately
UPLOAD_LIST="main.yaml nested-1-1.yaml"

# Check that S3 bucket exists, if not create a new one
if aws s3 ls s3://${CFN_BUCKET_NAME} 2>&1 | grep NoSuchBucket
then
    echo Creating Amazon S3 bucket ${CFN_BUCKET_NAME}
    aws s3 mb s3://${CFN_BUCKET_NAME} --region $DEPLOYMENT_REGION
fi
echo "Preparing content for publication to Amazon S3 s3://${CFN_BUCKET_NAME}/${PROJECT_NAME}"

## clean away any previous builds of the CFN
rm -fr ${CFN_OUTPUT_DIR}
mkdir -p ${CFN_OUTPUT_DIR}
rm -f build/*-${DEPLOYMENT_REGION}.zip
cp ${CFN_TEMPLATE_DIR}/*.yaml ${CFN_OUTPUT_DIR}

# Zip the source code
echo "Zipping the source code"
rm -f ${PROJECT_NAME}.zip
zip -r ${PROJECT_NAME}.zip . -x "*.pdf" -x "*.git*" -x "*.DS_Store*" -x "*.vscode*" -x "/build/*"

## Zip the templates
echo "Zipping CloudFormation templates in ${CFN_OUTPUT_DIR}"
zip -r build/cfn-templates-${DEPLOYMENT_REGION}.zip ${CFN_OUTPUT_DIR}/*.yaml

## publish templates to target AWS regions
echo "Publishing CloudFormation to ${DEPLOYMENT_REGION}"
echo "Clearing the project directory for ${PROJECT_NAME} in ${CFN_BUCKET_NAME}..."

aws s3 rm \
    s3://${CFN_BUCKET_NAME}/${PROJECT_NAME}/ \
    --recursive \
    --region ${DEPLOYMENT_REGION}

echo "Self-packaging the Cloudformation templates: ${SELF_PACKAGE_LIST}"
for fname in ${SELF_PACKAGE_LIST};
do
    sed -ie "s/< S3_CFN_STAGING_PATH >/${PROJECT_NAME}/" ${CFN_OUTPUT_DIR}/${fname}
    sed -ie "s/< S3_CFN_STAGING_BUCKET >/${CFN_BUCKET_NAME}/" ${CFN_OUTPUT_DIR}/${fname}
    sed -ie "s/< S3_CFN_STAGING_BUCKET_PATH >/${CFN_BUCKET_NAME}\/${PROJECT_NAME}/" ${CFN_OUTPUT_DIR}/${fname}
done

echo "Packaging Cloudformation templates: ${AWS_PACKAGE_LIST}"
for fname in ${AWS_PACKAGE_LIST};
do
    pushd ${CFN_OUTPUT_DIR}
    aws cloudformation package \
        --template-file ${fname} \
        --s3-bucket ${CFN_BUCKET_NAME} \
        --s3-prefix ${PROJECT_NAME} \
        --output-template-file ${fname}-packaged \
        --region ${DEPLOYMENT_REGION}
    popd
done

# copy source code .zip file to the S3 bucket
aws s3 cp ${PROJECT_NAME}.zip s3://${CFN_BUCKET_NAME}/${PROJECT_NAME}/

# push files to S3, note this does not 'package' the templates
echo "Copying cloudformation templates and files to S3: ${UPLOAD_LIST}"
for fname in ${UPLOAD_LIST};
do
    if [ -f ${CFN_OUTPUT_DIR}/${fname}-packaged ]; then
        aws s3 cp ${CFN_OUTPUT_DIR}/${fname}-packaged s3://${CFN_BUCKET_NAME}/${PROJECT_NAME}/${fname}
    else
        aws s3 cp ${CFN_OUTPUT_DIR}/${fname} s3://${CFN_BUCKET_NAME}/${PROJECT_NAME}/${fname}
    fi

    echo "To validate template ${fname}:"
    echo "aws cloudformation validate-template --template-url https://s3.${DEPLOYMENT_REGION}.amazonaws.com/${CFN_BUCKET_NAME}/${PROJECT_NAME}/${fname}"

    echo "To deploy stack execute:"
    echo "aws cloudformation create-stack --template-url https://s3.${DEPLOYMENT_REGION}.amazonaws.com/${CFN_BUCKET_NAME}/${PROJECT_NAME}/${fname} --region ${DEPLOYMENT_REGION} --stack-name <STACK_NAME> --disable-rollback --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM --parameters ParameterKey=,ParameterValue=" 

done

echo ==================================================
echo "Publication complete"
