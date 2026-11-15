# One Lambda layer from a directory already staged as a layer expects it: <dir>/python/<packages>.
# Building the directory (pip for Lambda's platform) is the caller's job; a new zip hash publishes a new version.

data "archive_file" "this" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${var.source_dir}.zip"
}

resource "aws_lambda_layer_version" "this" {
  layer_name               = var.name
  filename                 = data.archive_file.this.output_path
  source_code_hash         = data.archive_file.this.output_base64sha256
  compatible_runtimes      = var.compatible_runtimes
  compatible_architectures = var.compatible_architectures
}
