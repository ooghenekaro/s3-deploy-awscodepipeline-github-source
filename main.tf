data "aws_codestarconnections_connection" "github-aws" {
  arn = "arn:aws:codestar-connections:eu-west-2:335871625378:connection/a0dd4905-7501-41fd-96c3-7d504c11706a"
}


provider "aws" {
  region = "eu-west-2"
}

# Data source for the S3 bucket for our pipeline deploy
data "aws_s3_bucket" "deploy_bucket" {
  bucket   = "pipelinev2.rekeyole.com" 
}

# Artifact Bucket for Pipeline
 resource "aws_s3_bucket" "artifact_bucket" {
  bucket = "artifact-bucket-karotty"
}

# Define the CodePipeline
resource "aws_codepipeline" "static_site_pipeline" {
  name     = "static-site-pipeline"
  role_arn = aws_iam_role.codepipeline_role.arn


  artifact_store {
    location =data.aws_s3_bucket.deploy_bucket.bucket
    type     = "S3"

    encryption_key {
      id   = aws_kms_key.pipeline_key.arn
      type = "KMS"
    } 
  }

  stage {
    name = "Source"

    action {
      name             = "Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["source_artifact"]

      configuration = {
        FullRepositoryId = var.repo
        BranchName       = var.branch
        ConnectionArn    = data.aws_codestarconnections_connection.github-aws.arn
   
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name             = "S3Deploy"
      category         = "Deploy"
      owner            = "AWS"
      provider         = "S3"
      version          = "1"
      region           = "eu-west-2"
      input_artifacts  = ["source_artifact"]
      output_artifacts = []

      configuration = {
        BucketName = data.aws_s3_bucket.deploy_bucket.bucket
        Extract    = true
      }
    }
  }
}

# Codepipeline IAM role and permissions
data "aws_iam_policy_document" "assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["codepipeline.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "codepipeline_role" {
  name               = "codepipeline-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
}

data "aws_iam_policy_document" "codepipeline_policy" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetBucketVersioning",
      "s3:PutObjectAcl",
      "s3:PutObject",
    ]

    resources = [
      data.aws_s3_bucket.deploy_bucket.arn,
      "${data.aws_s3_bucket.deploy_bucket.arn}/*",
         aws_s3_bucket.artifact_bucket.arn,
      "${aws_s3_bucket.artifact_bucket.arn}/*"
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["codestar-connections:UseConnection"]
    resources = [data.aws_codestarconnections_connection.github-aws.arn]
  }

  statement {
    effect = "Allow"

    actions = [
      "kms:GenerateDataKey",
      "kms:Decrypt",
      "codebuild:BatchGetBuilds",
      "codebuild:StartBuild",
    ]

    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "codepipeline_policy" {
  name   = "codepipeline_policy"
  role   = aws_iam_role.codepipeline_role.id
  policy = data.aws_iam_policy_document.codepipeline_policy.json
}



# KMS key for artifact encryption
resource "aws_kms_key" "pipeline_key" {
  description = "KMS key for CodePipeline artifact encryption"
}

resource "aws_kms_alias" "pipeline_key_alias" {
  name          = "alias/pipeline-key"
  target_key_id = aws_kms_key.pipeline_key.id
}


