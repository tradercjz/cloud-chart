kubectl run net-test \
  --image=curlimages/curl:8.5.0 \
  --restart=Never \
  -it --rm -- sh


curl http://qwen-service:9999/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen-local",
    "messages": [
      {"role": "system", "content": "你是一个严谨的AI助手"},
      {"role": "user", "content": "用一句话解释什么是Kubernetes"}
    ],
    "temperature": 0.2,
    "max_tokens": 200
  }'
