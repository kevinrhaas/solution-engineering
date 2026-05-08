PAT_TOKEN=REDACTED_DATABRICKS_PAT 

curl -X GET \
  "https://dbc-19158583-c547.cloud.databricks.com/api/2.0/workspace/list?path=/Users/kevinroberthaas@gmail.com/pentaho" \
  -H "Authorization: Bearer $PAT_TOKEN"
