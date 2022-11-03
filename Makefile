#must read from .env...
setup:
	cp ./.env.sample ./.env
up:
	sh exec.sh
down:
	docker-compose -f ${DOCKER_FILE} down -v --remove-orphans
clean:
	rm function.zip \
		${AWS_LAMBDA_POLICY_FILE} \
		${DUMMY_FILE} \
		${AWS_LAMBDA_FILE_PATH} \
		${AWS_IAM_POLICY_FILE}
