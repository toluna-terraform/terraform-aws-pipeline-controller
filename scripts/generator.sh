APP_NAME="$(echo $1)"
ENV_NAME="$(echo $2)"
ENV_NAME_COLOR=$(echo $3)
if [ $ENV_NAME_COLOR == "blue" ] || [ $ENV_NAME_COLOR == "green" ]; then
    ENV_NAME_COLOR=$(echo $2-$3)
fi
export CONSUL_URL="$(echo $4)"
export CONSUL_HTTP_ADDR=https://$CONSUL_URL
export CONSUL_HTTP_TOKEN="$(echo $5)"

tar -zxvf inframap-linux-amd64.tar.gz
declare -a STATE_LAYERS=("app" "data" "shared")
for s in "${STATE_LAYERS[@]}"; do
    if [ $s == "app" ]; then
        DATA_WORKSPACE=$(consul kv get "terraform/${APP_NAME}/app-env.json" | jq -r ".${ENV_NAME}.data_workspace")
        SHARED_LAYER=$(consul kv get "terraform/${APP_NAME}/app-env.json" | jq -r ".${ENV_NAME}.env_type")
        echo $DATA_WORKSPACE;
        echo $SHARED_LAYER;
    fi
    if [ $s == "data" ]; then
        ENV_NAME_COLOR=$DATA_WORKSPACE
    elif [ $s == "shared" ]; then
        ENV_NAME_COLOR="shared-"$SHARED_LAYER
    fi
    CHECK=$(consul kv get "terraform/${APP_NAME}/$s/state-env:${ENV_NAME_COLOR}" | jq -r '."current-hash"')
    echo $CHECK
    if [ -z "$CHECK" ] || [ $CHECK == "null" ]; then
        STATE=$(consul kv get "terraform/${APP_NAME}/$s/state-env:${ENV_NAME_COLOR}")
        echo $STATE | jq | tee -a "$s".tfstate >/dev/null
    else
        STATE=$(curl -sS "$CONSUL_HTTP_ADDR/v1/kv/terraform/${APP_NAME}/$s/state-env:${ENV_NAME_COLOR}/?keys&token=$CONSUL_HTTP_TOKEN")
        KEYS=$(echo $STATE | jq -r '.' | tr -d '[],"')
        KEYS=($(echo $STATE | jq -r '.' | tr -d '[]," '))
        LAST_ELEMENT=$(echo ${KEYS[${#KEYS[@]}-1]})
        FETCH_STATE=""
        for row in "${KEYS[@]}"; do
            FETCH_STATE=$FETCH_STATE$(consul kv get "$row")
            if [ "$LAST_ELEMENT" = "$row" ]; then
                echo $FETCH_STATE | jq | tee -a "$s".tfstate >/dev/null
                echo $FETCH_STATE;
            fi
        done
    fi
    ./inframap-linux-amd64 generate "$s".tfstate | dot -Tpng > "$s"_graph.png
    aws s3 cp "$s"_graph.png s3://s3-codepipeline-${APP_NAME}-$SHARED_LAYER/inframap/
done