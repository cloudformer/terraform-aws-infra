# lambdaflow: Airflow 3 DAG files on Lambda, Step Functions, EventBridge Scheduler, DynamoDB and S3; a web console
# at the Function URL. ≈ $0 when nothing runs. https://github.com/cloudformer/lambdaflow
#
#   S3 bucket          dags/ (the DAG files, as in MWAA), logs/ (task logs)
#   DynamoDB table     DAGs, runs, task instances, XComs, import errors
#   Lambda console     Function URL: web console + JSON API; S3 events for dags/; keeps schedules in sync
#   Lambda worker      the only code that imports DAG files and runs tasks (low privilege + task_policy_arns)
#   Lambda layer       jinja2, tzdata
#   Step Functions     ONE generic state machine: start → step → run tasks (Map) → wait → step ...
#   Scheduler group    one EventBridge schedule per DAG, created by the console
#   SQS                dead-letter queue for schedules that could not start a run

data "aws_caller_identity" "me" {}
data "aws_region" "current" {}

locals {
  p              = var.project_name
  account        = data.aws_caller_identity.me.account_id
  package        = "lambdaflow==${var.lambdaflow_version}" # a release from PyPI, never a working tree
  layer_packages = "jinja2==3.1.6 tzdata==2025.2"
  bucket         = var.bucket != null ? var.bucket : "${local.p}-data-${local.account}"
}

# ---------------- storage ----------------
module "bucket" {
  source        = "../../components/s3_bucket"
  name          = local.bucket
  force_destroy = var.force_destroy
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket     = module.bucket.name
  depends_on = [module.bucket]

  rule {
    id     = "task-logs"
    status = "Enabled"
    filter {
      prefix = "logs/"
    }
    expiration {
      days = var.task_log_days
    }
  }
}

module "table" {
  source = "../../components/dynamodb_table"
  name   = local.p
}

module "dlq" {
  source = "../../components/sqs_queue"
  name   = "${local.p}-schedule-dlq"
}

# ---------------- packaging: lambdaflow from PyPI (lambdaflow.server) + its layer ----------------
data "external" "build" {
  program = ["python3", "${path.module}/build.py", local.package, local.layer_packages, "${path.module}/.build/lambdaflow"]
}

data "archive_file" "code" {
  type        = "zip"
  source_dir  = data.external.build.result.code
  excludes    = ["**/__pycache__/**", "dev.py", "__init__.py"] # the local runner; the pip package's marker
  output_path = "${path.module}/.build/server.zip"
}

module "layer" {
  source                   = "../../components/lambda_layer"
  name                     = "${local.p}-deps"
  source_dir               = data.external.build.result.layer
  compatible_architectures = ["arm64"]
}

# ---------------- the worker: imports DAG files, runs tasks ----------------
module "worker" {
  source = "../../components/lambda"

  function_name        = "${local.p}-worker"
  role_name            = "${local.p}-worker"
  policy_name          = "${local.p}-worker"
  function_url         = false # invoked by the state machine and the console only
  handler              = "worker.lambda_handler"
  runtime              = "python3.12"
  architecture         = "arm64"
  filename             = data.archive_file.code.output_path
  source_code_hash     = data.archive_file.code.output_base64sha256
  layers               = [module.layer.arn]
  timeout              = var.task_timeout
  memory_size          = var.worker_memory
  reserved_concurrency = -1
  log_retention_days   = var.cloudwatch_log_days
  policy_arns          = var.task_policy_arns # what task code may do: granted here and only here

  environment = merge(var.task_env, {
    TABLE              = module.table.name
    BUCKET             = module.bucket.name
    LAMBDAFLOW_CACHE   = "/tmp/lambdaflow"
    PAUSED_AT_CREATION = var.paused_at_creation ? "1" : "0"
  })

  policy_statements = [
    { Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query"],
    Resource = module.table.arn },
    { Effect = "Allow", Action = ["s3:GetObject"], Resource = ["${module.bucket.arn}/dags/*", "${module.bucket.arn}/logs/*"] },
    { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${module.bucket.arn}/logs/*" },
    { Effect = "Allow", Action = ["s3:ListBucket"], Resource = module.bucket.arn }, # a missing log reads as 404, not 403
  ]
}

# ---------------- the state machine: one execution per DAG run; the worker decides, this only loops ----------------
locals {
  lambda_retry = [{
    ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"]
    IntervalSeconds = 2, MaxAttempts = 6, BackoffRate = 2
  }]
  invoke = "arn:aws:states:::lambda:invoke"
  worker = module.worker.function_arn
  definition = {
    Comment = "lambdaflow: one DAG run. The worker decides everything; this only loops."
    StartAt = "Begin"
    States = {
      Begin = { # {"action": "start"} from EventBridge Scheduler, {"action": "resume"} from the console
        Type       = "Task", Resource = local.invoke, OutputPath = "$.Payload", Retry = local.lambda_retry, Next = "Go"
        Parameters = { FunctionName = local.worker, "Payload.$" = "$" }
      }
      Go = {
        Type    = "Choice", Default = "Done"
        Choices = [{ Variable = "$.go", BooleanEquals = true, Next = "Step" }]
      }
      Step = {
        Type       = "Task", Resource = local.invoke, OutputPath = "$.Payload", Next = "Route"
        Parameters = { FunctionName = local.worker, Payload = { action = "step", "dag_id.$" = "$.dag_id", "run_id.$" = "$.run_id" } }
        Retry      = concat(local.lambda_retry, [{ ErrorEquals = ["States.ALL"], IntervalSeconds = 5, MaxAttempts = 3, BackoffRate = 2 }])
      }
      Route = {
        Type    = "Choice", Default = "Wait"
        Choices = [{ Variable = "$.done", IsPresent = true, Next = "Done" }, { Variable = "$.tasks", IsPresent = true, Next = "RunTasks" }]
      }
      RunTasks = {
        Type         = "Map", ItemsPath = "$.tasks", MaxConcurrency = var.max_parallel_tasks, ResultPath = null, Next = "Step"
        ItemSelector = { "dag_id.$" = "$.dag_id", "run_id.$" = "$.run_id", "task_id.$" = "$$.Map.Item.Value" }
        ItemProcessor = {
          ProcessorConfig = { Mode = "INLINE" }
          StartAt         = "RunTask"
          States = {
            RunTask = {
              Type       = "Task", Resource = local.invoke, Retry = local.lambda_retry, End = true
              Parameters = { FunctionName = local.worker, Payload = { action = "run_task", "dag_id.$" = "$.dag_id", "run_id.$" = "$.run_id", "task_id.$" = "$.task_id" } }
              Catch      = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = "TaskFailed" }] # timeout, out of memory
            }
            TaskFailed = {
              Type       = "Task", Resource = local.invoke, Retry = local.lambda_retry, End = true
              Parameters = { FunctionName = local.worker, Payload = { action = "task_failed", "dag_id.$" = "$.dag_id", "run_id.$" = "$.run_id", "task_id.$" = "$.task_id", "error.$" = "$.error" } }
            }
          }
        }
      }
      Wait = { Type = "Wait", SecondsPath = "$.wait", Next = "Step" }
      Done = { Type = "Succeed" }
    }
  }
}

module "run" {
  source     = "../../components/step_function"
  name       = "${local.p}-run"
  role_name  = "${local.p}-states"
  definition = local.definition
  policy_statements = [
    { Effect = "Allow", Action = "lambda:InvokeFunction", Resource = [local.worker, "${local.worker}:*"] },
  ]
}

# ---------------- EventBridge Scheduler: the group and the role its schedules run as; the schedules are the console's ----------------
module "schedules" {
  source    = "../../components/scheduler_group"
  name      = local.p
  role_name = "${local.p}-scheduler"
  policy_statements = [
    { Effect = "Allow", Action = "states:StartExecution", Resource = module.run.arn },
    { Effect = "Allow", Action = "sqs:SendMessage", Resource = module.dlq.arn },
  ]
}

# ---------------- the console: Function URL, S3 events, schedules ----------------
module "console" {
  source = "../../components/lambda"

  function_name        = "${local.p}-console"
  role_name            = "${local.p}-console"
  policy_name          = "${local.p}-console"
  handler              = "lambda_function.lambda_handler"
  runtime              = "python3.12"
  architecture         = "arm64"
  filename             = data.archive_file.code.output_path
  source_code_hash     = data.archive_file.code.output_base64sha256
  layers               = [module.layer.arn]
  timeout              = 60 # an upload waits for the worker to parse the file
  memory_size          = 512
  reserved_concurrency = -1
  log_retention_days   = var.cloudwatch_log_days
  url_auth             = var.function_url_auth

  environment = {
    USER_NAME          = var.console_auth_username
    PASSWORD           = var.console_auth_password
    CONSOLE            = var.console ? "1" : "0"
    TABLE              = module.table.name
    BUCKET             = module.bucket.name
    WORKER_FUNCTION    = module.worker.function_name
    STATE_MACHINE_ARN  = module.run.arn
    SCHEDULE_GROUP     = module.schedules.name
    SCHEDULER_ROLE_ARN = module.schedules.role_arn
    DLQ_ARN            = module.dlq.arn
    PAUSED_AT_CREATION = var.paused_at_creation ? "1" : "0"
  }

  policy_statements = [
    { Effect = "Allow", Action = ["dynamodb:GetItem", "dynamodb:PutItem", "dynamodb:UpdateItem", "dynamodb:DeleteItem", "dynamodb:Query", "dynamodb:BatchWriteItem"],
    Resource = module.table.arn },
    { Effect = "Allow", Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"], Resource = ["${module.bucket.arn}/dags/*", "${module.bucket.arn}/logs/*"] },
    { Effect = "Allow", Action = ["s3:ListBucket"], Resource = module.bucket.arn },
    { Effect = "Allow", Action = "lambda:InvokeFunction", Resource = local.worker },
    { Effect = "Allow", Action = "states:StartExecution", Resource = module.run.arn },
    { Effect = "Allow", Action = ["scheduler:GetSchedule", "scheduler:CreateSchedule", "scheduler:UpdateSchedule", "scheduler:DeleteSchedule"],
    Resource = "arn:aws:scheduler:${data.aws_region.current.region}:${local.account}:schedule/${module.schedules.name}/*" },
    { Effect = "Allow", Action = "iam:PassRole", Resource = module.schedules.role_arn,
    Condition = { StringEquals = { "iam:PassedToService" = "scheduler.amazonaws.com" } } },
  ]
}

# DAG files copied straight to s3://<bucket>/dags/ are parsed too
resource "aws_lambda_permission" "s3" {
  statement_id   = "AllowS3DagEvents"
  action         = "lambda:InvokeFunction"
  function_name  = module.console.function_name
  principal      = "s3.amazonaws.com"
  source_arn     = module.bucket.arn
  source_account = local.account
}

resource "aws_s3_bucket_notification" "dags" {
  bucket = module.bucket.name
  lambda_function {
    lambda_function_arn = module.console.function_arn
    events              = ["s3:ObjectCreated:*", "s3:ObjectRemoved:*"]
    filter_prefix       = "dags/"
    filter_suffix       = ".py"
  }
  depends_on = [aws_lambda_permission.s3]
}
