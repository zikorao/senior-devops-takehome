# kind 0.33 and deploy/kind/cluster.yaml stay the cluster definition, including the
# kubelet node-label patch ingress-nginx expects. Terraform creates that cluster
# when it is missing and deletes it on destroy. A config change replaces it.

resource "terraform_data" "cluster" {
  input = var.cluster_name

  triggers_replace = [
    filesha256("${path.module}/../kind/cluster.yaml"),
  ]

  provisioner "local-exec" {
    command = "bash \"${path.module}/create-cluster.sh\""
    environment = {
      CLUSTER_NAME   = var.cluster_name
      CLUSTER_CONFIG = abspath("${path.module}/../kind/cluster.yaml")
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "export PATH=\"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$${PATH}\"; kind delete cluster --name ${self.output}"
  }
}

# Integration-test Compose volumes are not part of the cluster. Destroy removes them.
resource "terraform_data" "compose" {
  input = abspath("${path.module}/../../compose.dependencies.yaml")

  provisioner "local-exec" {
    command = "true"
  }

  provisioner "local-exec" {
    when       = destroy
    on_failure = continue
    command    = "export PATH=\"/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$${PATH}\"; docker compose -f '${self.output}' down -v"
  }
}
