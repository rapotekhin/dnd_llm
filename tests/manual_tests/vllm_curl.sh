# Call the server using curl:
curl -X POST "http://localhost:8999/v1/chat/completions" \
	-H "Content-Type: application/json" \
	--data '{
		"model": "Vikhrmodels/QVikhr-3-4B-Instruction",
		"messages": [
			{
				"role": "user",
				"content": "What is the capital of France?"
			}
		]
	}'