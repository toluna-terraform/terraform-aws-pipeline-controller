locals {
  prefix = "codebuild"
  codebuild_name = "source"
  app_name = var.app_name
  env_name = var.env_name
  env_type = var.env_type
  aws_account_id = data.aws_caller_identity.current.account_id
  suffix = "${var.app_name}-${var.env_name}"
  source_repository_url = "https://bitbucket.org/${var.source_repository}"
}

resource "aws_codebuild_webhook" "pr_flow_hook_webhook" {
  project_name = aws_codebuild_project.pr_codebuild.name
  build_type   = "BUILD"
  filter_group {
    filter {
      type    = "EVENT"
      pattern = var.pipeline_type == "dev" ? "PUSH" : "PULL_REQUEST_CREATED,PULL_REQUEST_UPDATED"
    }

    filter {
      type    = var.pipeline_type == "dev" ? "HEAD_REF" : "BASE_REF"
      pattern = "^refs/heads/${var.trigger_branch}$"
    }

    filter {
      type    = "FILE_PATH"
      pattern = var.pipeline_type == "dev" ? ".*" : "${var.path_pattern}"
    }
  }
}

resource "aws_codebuild_webhook" "merge_flow_hook_webhook" {
  count        = var.pipeline_type == "dev" ? 0 : 1
  project_name = aws_codebuild_project.merge_codebuild[count.index].name
  build_type   = "BUILD"
  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PULL_REQUEST_MERGED"
    }

    filter {
      type    = "BASE_REF"
      pattern = "^refs/heads/${var.trigger_branch}$"
    }

    filter {
      type    = "FILE_PATH"
      pattern = var.path_pattern
    }
  }
}

resource "aws_codebuild_webhook" "merge_dev_flow_hook_webhook" {
  count        = var.pipeline_type == "dev" && var.app_type == "sam" ? 1 : 0
  project_name = aws_codebuild_project.merge_codebuild[count.index].name
  build_type   = "BUILD"
  filter_group {
    filter {
      type    = "EVENT"
      pattern = "PUSH"
    }

    filter {
      type    = "HEAD_REF"
      pattern = "^refs/heads/${var.trigger_branch}$"
    }

    filter {
      type    = "FILE_PATH"
      pattern = var.path_pattern
    }
  }
}

resource "aws_codebuild_project" "pr_codebuild" {
  name          = var.pipeline_type == "dev" ? "${local.prefix}-${local.codebuild_name}-push-${local.suffix}" : "${local.prefix}-${local.codebuild_name}-pr-${local.suffix}"
  description   = "Pull source files from Git repo"
  build_timeout = "120"
  service_role  = aws_iam_role.source_codebuild_iam_role.arn

  artifacts {
    packaging              = "ZIP"
    type                   = "S3"
    override_artifact_name = true
    location               = "s3-codepipeline-${var.app_name}-${var.env_type}"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/code_build/${local.codebuild_name}/log-group"
      stream_name = "/code_build/${local.codebuild_name}/stream"
    }
  }

  source {
    type      = "BITBUCKET"
    location  = local.source_repository_url
    buildspec = templatefile("${path.module}/templates/pr-created-buildspec-source.yml.tpl",
    { env_name = var.env_name,
      env_type = var.env_type,
      app_name = var.app_name,
      domain = var.domain,
      source_repository = var.source_repository,
      is_managed_env = var.is_managed_env,
      pipeline_type = var.pipeline_type,
      aws_profile = var.aws_profile,
      tribe_state_bucket = var.tribe_state_bucket
      })
    }
    tags = tomap({
      Name        = "${local.prefix}-${local.codebuild_name}",
      environment = "${var.env_name}",
      created_by  = "terraform"
    })
}

resource "aws_codebuild_project" "merge_codebuild" {
  count         = var.pipeline_type != "dev" || var.app_type == "sam" ? 1 : 0
  name          = "${local.prefix}-${local.codebuild_name}-merge-${local.suffix}"
  description   = "Pull source files from Git repo"
  build_timeout = "120"
  service_role  = aws_iam_role.source_codebuild_iam_role.arn

  artifacts {
    packaging              = "ZIP"
    type                   = "S3"
    override_artifact_name = true
    location               = "s3-codepipeline-${var.app_name}-${var.env_type}"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/code_build/${local.codebuild_name}/log-group"
      stream_name = "/code_build/${local.codebuild_name}/stream"
    }
  }

  source {
    type     = "BITBUCKET"
    location = local.source_repository_url
    buildspec = var.app_type == "ecs" ? templatefile("${path.module}/templates/merge-buildspec-source.yml.tpl",
      {
        env_name       = var.env_name,
        env_type       = var.env_type,
        app_name       = var.app_name,
        app_type       = var.app_type,
        domain         = var.domain,
        aws_profile    = var.aws_profile
        ttl            = var.ttl
        tribe_state_bucket = var.tribe_state_bucket
      }) : var.app_type == "sam" ? templatefile("${path.module}/templates/sam-merge-buildspec-source.yml.tpl",
      {
        env_name       = var.env_name,
        env_type       = var.env_type,
        app_name       = var.app_name,
        app_type       = var.app_type,
        domain         = var.domain,
        aws_profile    = var.aws_profile
        ttl            = var.ttl
        tribe_state_bucket = var.tribe_state_bucket
      }) : templatefile("${path.module}/templates/spa-merge-buildspec-source.yml.tpl",
      {
        env_name       = var.env_name,
        env_type       = var.env_type,
        app_name       = var.app_name,
        domain         = var.domain,
        app_type       = var.app_type,
        aws_profile    = var.aws_profile
        tribe_state_bucket = var.tribe_state_bucket
    })
  }
  tags = tomap({
    Name        = "${local.prefix}-${local.codebuild_name}",
    environment = "${var.env_name}",
    created_by  = "terraform"
  })
}

resource "aws_iam_role" "source_codebuild_iam_role" {
  name               = "role-${var.app_name}-${var.env_type}-${local.codebuild_name}-bg-${var.env_name}"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume_role_policy.json
}

resource "aws_iam_role_policy_attachment" "source_codebuild_iam_policy" {
  role       = aws_iam_role.source_codebuild_iam_role.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess" // this policy should be changed to a new policy.
}

resource "aws_s3_object" "folder" {
  bucket = var.bucket_id
  acl    = "private"
  key    = "${var.env_name}/${var.pipeline_type}"
}
