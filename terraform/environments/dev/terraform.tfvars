aws_region = "us-east-1"

project_name    = "project-foxtrot"
domain_name     = "alexanderkachar.com"
app_host        = "todo.alexanderkachar.com"
monitoring_host = "monitoring.alexanderkachar.com"

github_repo                        = "alexkachar/eks-pipeline-project-foxtrot"
runner_github_token_parameter_name = "/github/actions/foxtrot/pat"

developer_ip_cidrs          = ["5.29.10.1/32", "77.137.68.203/32"]
wireguard_client_public_key = "6V76gueZCzjwpuw5wlmHXDGQbJodb6tfGrpoAZkzMB0="
enable_cluster_addons       = true

alb_dns_name            = "k8s-todoapppublic-ee3b245395-1012844162.us-east-1.elb.amazonaws.com"
monitoring_alb_dns_name = "internal-k8s-todoappmonitoring-458f40e01d-172795507.us-east-1.elb.amazonaws.com"
