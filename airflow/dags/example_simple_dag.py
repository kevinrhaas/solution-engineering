"""
Example DAG for getting started with Airflow.
"""

from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.operators.bash import BashOperator


def print_hello():
    """Simple Python function."""
    print("Hello from Airflow!")


def print_env_vars():
    """Print environment information."""
    import os
    print(f"Home: {os.path.expanduser('~')}")
    print(f"Current time: {datetime.now()}")


def process_data():
    """Simulate data processing."""
    data = {"message": "Processing data", "count": 42}
    print(f"Processing: {data}")
    return data


# Define default arguments for the DAG
default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime(2024, 1, 1),
    'email_on_failure': False,
    'email_on_retry': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# Create the DAG
with DAG(
    'example_simple_dag',
    default_args=default_args,
    description='A simple example DAG',
    schedule_interval='@daily',  # Run daily
    catchup=False,
    tags=['example', 'simple'],
) as dag:

    # Task 1: Print hello
    task_hello = PythonOperator(
        task_id='hello_task',
        python_callable=print_hello,
    )

    # Task 2: Print environment
    task_env = PythonOperator(
        task_id='env_task',
        python_callable=print_env_vars,
    )

    # Task 3: Process data
    task_process = PythonOperator(
        task_id='process_task',
        python_callable=process_data,
    )

    # Task 4: Bash command
    task_bash = BashOperator(
        task_id='bash_task',
        bash_command='echo "Running bash command" && date',
    )

    # Define task dependencies
    task_hello >> task_env >> task_process >> task_bash
