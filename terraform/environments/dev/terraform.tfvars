aws_region = "us-east-1"

project_name    = "project-foxtrot"
domain_name     = "alexanderkachar.com"
app_host        = "todo.alexanderkachar.com"
monitoring_host = "monitoring.alexanderkachar.com"

github_repo                        = "alexkachar/eks-pipeline-project-foxtrot"
runner_github_token_parameter_name = "/github/actions/foxtrot/pat"

developer_ip_cidr           = "5.29.10.1/32"
wireguard_client_public_key = "6V76gueZCzjwpuw5wlmHXDGQbJodb6tfGrpoAZkzMB0="
enable_cluster_addons       = true

# Fill after the public ALB exists, then run terraform apply again for Route 53.
alb_dns_name = ""
