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
      - yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
      - yum -y install terraform
      - printf "%s\n%s\nus-east-1\njson" | aws configure --profile ${app_name}-non-prod
      - printf "%s\n%s\nus-east-1\njson" | aws configure --profile ${app_name}-prod
      - |
        ### Finishing Deployment/s #####
        DEPLOYMENT_DETAILS=$(aws dynamodb get-item --table-name MergeWaiter-${app_name}-${env_type} --key '{"APPLICATION" :{"S":"${app_name}-${env_name}"}}' --attributes-to-get '["Details"]' --query 'Item.Details.L[].M')
        for row in $(echo "$${DEPLOYMENT_DETAILS}" | jq -r '.[] | @base64'); do
          _jq() {
            echo $${row} | base64 --decode | jq -r $${1}
            }
          DEPLOYMENT_ID=$(_jq '.DeploymentId.S')
          HOOK_EXECUTION_ID=$(_jq '.LifecycleEventHookExecutionId.S')
          aws deploy put-lifecycle-event-hook-execution-status --deployment-id $DEPLOYMENT_ID --lifecycle-event-hook-execution-id $HOOK_EXECUTION_ID --status Succeeded --output text
        done
        aws dynamodb delete-item --table-name MergeWaiter-${app_name}-${env_type} --key '{"APPLICATION" :{"S":"${app_name}-${env_name}"}}'
  build:
    on-failure: ABORT
    commands:
      - |
        export INFRA_CHANGED=$(aws s3 cp "s3://${tribe_state_bucket}/infra/${app_name}-${env_name}/infra_changed" - || echo "")
        if [ "$INFRA_CHANGED" == "true" ]; then
          export CURRENT_COLOR=$(aws s3 cp "s3://${tribe_state_bucket}/infra/${app_name}-${env_name}/current_color" - || echo "")
          if [ "$CURRENT_COLOR" != "green" ] && [ "$CURRENT_COLOR" != "blue" ]; then
            echo "Creating Green route"
            NEXT_COLOR="green"
            CURRENT_COLOR="white"
            CURRENT_RECORD="DUMMY_Blue"
          else
            echo "switching colors"
            if [[ $CURRENT_COLOR == "green" ]]; then
              NEXT_COLOR="blue"
              CURRENT_COLOR="green"
            else
              NEXT_COLOR="green"
              CURRENT_COLOR="blue"
            fi
          fi
          aws s3 rm "s3://${tribe_state_bucket}/infra/${app_name}-${env_name}/infra_changed"
          echo -n $NEXT_COLOR | aws s3 cp - "s3://${tribe_state_bucket}/infra/${app_name}-${env_name}/current_color" --content-type "text/plain"
          echo "Shifting traffic"
          cd $CODEBUILD_SRC_DIR/terraform/shared
          terraform init
          terraform workspace select shared-${env_type}
          terraform init
          terraform apply -target=module.dns -auto-approve || exit 1
          cd $CODEBUILD_SRC_DIR/terraform/app
          terraform init
          if [[ "$CURRENT_COLOR" == "white" ]]; then
            terraform workspace select ${env_name}
          else
            terraform workspace select ${env_name}-$CURRENT_COLOR
          fi
          echo "Waiting ${ttl} seconds for DNS Cache to refresh"
          sleep ${ttl}
          echo "Destroying old environment"
          cd $CODEBUILD_SRC_DIR/terraform/app
          terraform init
          terraform destroy -auto-approve
          terraform workspace select ${env_name}-$NEXT_COLOR
          if [[ "$CURRENT_COLOR" == "white" ]]; then
            terraform workspace delete ${env_name}
          else
            terraform workspace delete ${env_name} || echo "no base workspace to delete"
            terraform workspace delete ${env_name}-$CURRENT_COLOR
          fi
        fi
