# Use the official AWS Lambda Python 3.13 runtime
FROM public.ecr.aws/lambda/python:3.13

# Set working directory
# WORKDIR ${LAMBDA_TASK_ROOT}

# Copy the requirements.txt file
COPY requirements.txt ${LAMBDA_TASK_ROOT}

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the lambda function code
COPY src/ ${LAMBDA_TASK_ROOT}

# Set the Lambda handler
CMD [ "lambda_function.handler" ] 