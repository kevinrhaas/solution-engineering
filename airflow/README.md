# Apache Airflow Setup

Getting started with Apache Airflow for workflow orchestration.

## Project Structure

```
airflow/
├── dags/              # DAG definitions
├── logs/              # Airflow logs
├── plugins/           # Custom plugins and operators
├── .env               # Environment variables
├── requirements.txt   # Python dependencies
└── airflow.db         # SQLite database (created after init)
```

## Installation & Setup

### 1. Create a Virtual Environment

```bash
cd airflow
python3 -m venv venv
source venv/bin/activate
```

### 2. Install Dependencies

```bash
pip install --upgrade pip
pip install -r requirements.txt
```

### 3. Initialize Airflow

```bash
export AIRFLOW_HOME=$(pwd)
airflow db init
```

### 4. Create an Admin User

```bash
airflow users create \
  --username admin \
  --firstname Admin \
  --lastname User \
  --role Admin \
  --email admin@example.com \
  --password admin
```

### 5. Start the Web Server

In one terminal:
```bash
airflow webserver --port 8080
```

### 6. Start the Scheduler (in another terminal)

```bash
airflow scheduler
```

## Access the UI

- **Web UI**: http://localhost:8080
- **Username**: admin
- **Password**: admin

## Running Example DAG

Once both the webserver and scheduler are running:

1. Go to http://localhost:8080
2. Look for the `example_simple_dag` in the DAG list
3. Click on it and toggle it to "ON" (the switch on the top left)
4. Click "Trigger DAG" to run an instance

## Creating Your First DAG

Create a new Python file in the `dags/` directory. Example:

```python
from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator

def hello_world():
    print("Hello from Airflow!")

default_args = {
    'owner': 'airflow',
    'start_date': datetime(2024, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

with DAG(
    'my_first_dag',
    default_args=default_args,
    description='My first DAG',
    schedule_interval='@daily',
    catchup=False,
) as dag:
    
    task_1 = PythonOperator(
        task_id='hello_task',
        python_callable=hello_world,
    )
```

Save it and it will automatically appear in the Airflow UI.

## Useful Commands

```bash
# List all DAGs
airflow dags list

# List all tasks in a DAG
airflow tasks list <dag_id>

# Trigger a DAG
airflow dags trigger <dag_id>

# Check DAG syntax
airflow dags test <dag_id>

# View logs
airflow logs -d <dag_id> -t <task_id>

# Stop webserver
lsof -ti:8080 | xargs kill -9
```

## Notes

- This setup uses SQLite for simplicity (good for development)
- For production, use PostgreSQL or MySQL
- The SequentialExecutor runs tasks one at a time
- For parallel task execution, use LocalExecutor or CeleryExecutor
