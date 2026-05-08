touch monkey-nose.txt
aws bedrock-runtime invoke-model --profile khaas --region us-east-1 --model-id amazon.titan-text-lite-v1 --cli-binary-format raw-in-base64-out   --body '{"inputText":"What is your favorite color"}' out.json
