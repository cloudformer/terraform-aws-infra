output "console_url" {
  description = "Open in a browser (web console); the same URL is the JSON API and the host for lambdaflow.client"
  value       = module.console.url
}

output "dags_folder" {
  description = "Upload DAG files here as in MWAA (aws s3 cp my_dag.py <dags_folder>), or in the console"
  value       = "s3://${module.bucket.name}/dags/"
}

output "bucket" {
  value = module.bucket.name
}

output "worker_role" {
  description = "The role task code runs as; widen it only with task_policy_arns"
  value       = module.worker.role_arn
}

output "state_machine" {
  description = "One execution per DAG run (Step Functions console: the run's steps and timings)"
  value       = module.run.arn
}

output "schedule_group" {
  description = "EventBridge Scheduler group: one schedule per DAG, kept in sync by the console"
  value       = module.schedules.name
}
