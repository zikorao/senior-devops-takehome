variable "cluster_name" {
  description = "kind cluster name. Host port 8080 is published by deploy/kind/cluster.yaml."
  type        = string
  default     = "takehome"
}

variable "image_tag" {
  description = "API, worker, and mock tag loaded into kind. Use local for the :local and mock :1.0.0 tags, or the 12-character git SHA used by CI."
  type        = string
  default     = "local"

  validation {
    condition     = length(var.image_tag) > 0 && length(var.image_tag) <= 128
    error_message = "image_tag must be a non-empty Docker tag."
  }
}
