resource "random_password" "rabbitmq" {
  length  = 32
  special = false
}

resource "random_password" "redis" {
  length  = 32
  special = false
}

locals {
  kustomize_files = fileset("${path.module}/../kustomize", "*.yaml")
  kustomize_hash = sha256(join("", [
    for name in local.kustomize_files : filesha256("${path.module}/../kustomize/${name}")
  ]))
  rabbitmq_password = random_password.rabbitmq.result
  redis_password    = random_password.redis.result
}

resource "terraform_data" "bootstrap" {
  depends_on = [terraform_data.cluster]

  triggers_replace = [
    var.image_tag,
    local.kustomize_hash,
  ]

  lifecycle {
    replace_triggered_by = [terraform_data.cluster]
  }

  provisioner "local-exec" {
    command = "bash \"${path.module}/bootstrap.sh\""
    environment = {
      CLUSTER_NAME      = var.cluster_name
      IMAGE_TAG         = var.image_tag
      REPO_ROOT         = abspath("${path.module}/../..")
      RABBITMQ_PASSWORD = local.rabbitmq_password
      REDIS_PASSWORD    = local.redis_password
    }
  }
}
