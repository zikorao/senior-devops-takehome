// Preferred pipeline. GitHub Actions runs the same scripts on this public repository.
// A Jenkins agent needs Git, Python 3.12, Docker Compose, Terraform, kind, kubectl, and openssl.
// Set DOCKER_REGISTRY and bind credential id docker-registry for a remote registry push.
// Leave DOCKER_REGISTRY empty to load immutable tags into the local kind node.
// An unhealthy rollout or a failed smoke test fails the build.

pipeline {
    agent any
    options {
        timestamps()
        disableConcurrentBuilds()
    }
    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        stage('Test') {
            steps {
                sh './scripts/ci-local.sh test'
            }
        }
        stage('Build') {
            steps {
                sh './scripts/ci-local.sh build'
            }
        }
        stage('Push') {
            steps {
                sh './scripts/ci-local.sh push'
            }
        }
        stage('Deploy') {
            steps {
                sh './scripts/ci-local.sh deploy'
            }
        }
        stage('Smoke') {
            steps {
                sh './scripts/ci-local.sh smoke'
            }
        }
    }
}
