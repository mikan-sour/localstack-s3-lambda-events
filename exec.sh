#/bin/bash
ENV_FILE=./.env

function fail() {
    echo $2
    exit $1
}

if [[ -f $ENV_FILE ]]; then
    echo "Sourcing environment variables..."
    source $ENV_FILE
else
    fail 9 "$ENV_FILE not present..."
fi

echo "Removing old containers and lambda functions..."
rm function.zip \
$AWS_LAMBDA_POLICY_FILE \
$DUMMY_FILE \
$AWS_IAM_POLICY_FILE \
out
rm -rf $AWS_LAMBDA_FILE_PATH 

docker-compose -f ${DOCKER_FILE} down -v --remove-orphans

echo "Building new localstack environment..."
docker-compose -f ${DOCKER_FILE} up -d

echo "Prepare lambda..."
mkdir lambda
npx tsc
cp ./src/package.json ./lambda
cp -r ./src/node_modules ./lambda
cd ./lambda && zip -r function.zip . && cd..

sleep 3

echo "Creating bucket ${AWS_S3_BUCKET_ONE}..."
aws s3api create-bucket --endpoint-url=${AWS_ENDPOINT} --bucket=${AWS_S3_BUCKET_ONE} --region=${AWS_DEFAULT_REGION}

echo "${AWS_S3_BUCKET_ONE} arn..."


echo "Creating bucket ${AWS_S3_BUCKET_TWO}..."
aws s3api create-bucket \
--endpoint-url=${AWS_ENDPOINT} \
--bucket=${AWS_S3_BUCKET_TWO} \
--region=${AWS_DEFAULT_REGION}


echo "Create iam role and policy..."
cat <<EOF > $AWS_IAM_POLICY_FILE
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "Sid0",
            "Effect": "Allow",
            "Action": [
                "s3:GetObject",
                "s3:DeleteObject"
            ],
            "Resource": "arn:aws:s3:::${AWS_S3_BUCKET_ONE}/*"
        },
        {
            "Sid": "Sid1",
            "Effect": "Allow",
            "Action": "s3:ListBucket",
            "Resource": [
                "arn:aws:s3:::${AWS_S3_BUCKET_ONE}/*",
                "arn:aws:s3:::${AWS_S3_BUCKET_ONE}"
            ]
        },
        {
            "Sid": "Sid2",
            "Effect": "Allow",
            "Action": "s3:PutObject",
            "Resource": "arn:aws:s3:::${AWS_S3_BUCKET_TWO}/*"
        },
        {
            "Sid": "Sid3",
            "Effect": "Allow",
            "Action": [
                "logs:PutLogEvents",
                "logs:CreateLogGroup",
                "logs:CreateLogStream"
            ],
            "Resource": "arn:aws:logs:*:*:*"
        }
    ]
}
EOF

echo "Creating IAM policy..."
aws --endpoint-url=${AWS_ENDPOINT} \
    iam create-policy \
    --region=${AWS_DEFAULT_REGION} \
    --policy-name my-pol \
    --policy-document file://$AWS_IAM_POLICY_FILE 

echo "Creating IAM role..."
aws --endpoint-url=${AWS_ENDPOINT} \
    iam create-role --role-name lambda-ex \
    --region=${AWS_DEFAULT_REGION} \
    --assume-role-policy-document '{"Version": "2012-10-17","Statement": [{ "Effect": "Allow", "Principal": {"Service": "lambda.amazonaws.com"}, "Action": "sts:AssumeRole"}]}'

echo "Attaching IAM role policy..."
aws --endpoint-url=${AWS_ENDPOINT} \
    iam attach-role-policy \
    --policy-arn arn:aws:iam::aws:policy/service-role/AmazonS3ObjectLambdaExecutionRolePolicy \
    --role-name lambda-ex

echo "PUT IAM inline policy..."
aws --endpoint-url=${AWS_ENDPOINT} \
    iam put-role-policy \
    --role-name lambda-ex \
    --policy-name my-pol \
    --policy-document file://$AWS_IAM_POLICY_FILE 

echo "Deploying lambda..."
cd ./lambda
aws --endpoint-url=${AWS_ENDPOINT} \
    lambda create-function \
    --region=${AWS_DEFAULT_REGION} \
    --function-name=${AWS_LAMBDA_FUNCTION_NAME} \
    --zip-file=fileb://function.zip \
    --handler=index.handler --runtime nodejs12.x \
    --role=arn:aws:iam::000000000000:role/lambda-ex 

echo "Update function's env vars..."
aws --endpoint-url=${AWS_ENDPOINT} \
    lambda update-function-configuration --function-name ${AWS_LAMBDA_FUNCTION_NAME} \
    --region=${AWS_DEFAULT_REGION} \
    --environment "Variables={AWS_ENDPOINT=${AWS_ENDPOINT},AWS_S3_BUCKET_ONE=${AWS_S3_BUCKET_ONE},AWS_S3_BUCKET_TWO=${AWS_S3_BUCKET_TWO},DUMMY_FILE=${DUMMY_FILE}}"

echo "Add permission to lambda..."
aws --endpoint-url=${AWS_ENDPOINT} \
    lambda add-permission \
    --function-name "arn:aws:lambda:${AWS_DEFAULT_REGION}:000000000000:function:${AWS_LAMBDA_FUNCTION_NAME}"\
    --principal arn:aws:s3:::${AWS_S3_BUCKET_ONE} \
    --statement-id S3StatementId \
    --action "lambda:InvokeFunction" \
    --source-arn arn:aws:s3:::${AWS_S3_BUCKET_ONE} \
    --region=${AWS_DEFAULT_REGION}

cd ..

echo "Create lambda policy..."
cat <<EOF > $AWS_LAMBDA_POLICY_FILE
{
    "LambdaFunctionConfigurations": [
        {
            "Id": "s3eventtriggerslambda",
            "LambdaFunctionArn": "arn:aws:lambda:${AWS_DEFAULT_REGION}:000000000000:function:${AWS_LAMBDA_FUNCTION_NAME}",
            "Events": ["s3:ObjectCreated:*"]
        }
    ]
}
EOF

echo "Adding policy to ${AWS_S3_BUCKET_ONE}..."
aws --endpoint-url=${AWS_ENDPOINT} \
    s3api put-bucket-notification-configuration \
    --bucket=${AWS_S3_BUCKET_ONE} \
    --region=${AWS_DEFAULT_REGION} \
    --notification-configuration=file://$AWS_LAMBDA_POLICY_FILE


echo "Making dummy file for upload..."
touch $DUMMY_FILE
echo "Hey there?" >> $DUMMY_FILE

aws --endpoint-url=${AWS_ENDPOINT} \
    s3api put-object \
    --bucket=${AWS_S3_BUCKET_ONE} \
    --region=${AWS_DEFAULT_REGION} \
    --key=$DUMMY_FILE \
    --body=$DUMMY_FILE


echo "Now let's see dem logs!"
sleep 2
# aws --endpoint-url=${AWS_ENDPOINT} lambda invoke --function-name ${AWS_LAMBDA_FUNCTION_NAME} out --log-type Tail --query 'LogResult' --output text |  base64 -d
aws s3api list-objects --bucket=${AWS_S3_BUCKET_TWO} --endpoint-url=${AWS_ENDPOINT} --region=${AWS_DEFAULT_REGION} 

echo "Cleanup..."
rm -rf $AWS_LAMBDA_FILE_PATH \
$AWS_LAMBDA_POLICY_FILE \
$DUMMY_FILE \
$AWS_IAM_POLICY_FILE \
out

echo "DONE"
