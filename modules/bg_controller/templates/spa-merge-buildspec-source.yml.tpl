# code_build spec for pulling source from BitBucket
version: 0.2

env:
  parameter-store:
    USER: "/app/bb_user"
    PASS: "/app/bb_app_pass"

phases:
  pre_build:
    commands:
      - yum install -y yum-utils
      - printf "%s\n%s\nus-east-1\njson" | aws configure --profile ${app_name}-non-prod
      - printf "%s\n%s\nus-east-1\njson" | aws configure --profile ${app_name}-prod
  build:
    on-failure: ABORT
    commands:
      - |
        executionToken=$(aws codepipeline get-pipeline-state --name codepipeline-${app_name}-${env_name} --query 'stageStates[?stageName==`Deploy`].actionStates[2].latestExecution.token' --output text)
        echo "{" > approvalstage-approved.json
        echo "\"pipelineName\": \"codepipeline-${app_name}-${env_name}\","  >> approvalstage-approved.json
        echo "\"stageName\": \"Deploy\","  >> approvalstage-approved.json
        echo "\"actionName\": \"Merge-Waiter\","  >> approvalstage-approved.json
        echo "\"token\": \"$executionToken\","  >> approvalstage-approved.json
        echo "\"result\": {"  >> approvalstage-approved.json
        echo "\"status\": \"Approved\","  >> approvalstage-approved.json
        echo "\"summary\": \"Traffic will now shift to new deployment\""  >> approvalstage-approved.json
        echo "}"  >> approvalstage-approved.json
        echo "}"  >> approvalstage-approved.json
        aws codepipeline put-approval-result --cli-input-json file://approvalstage-approved.json

