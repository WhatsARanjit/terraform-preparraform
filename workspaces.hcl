"myworkspace" {
  prefix = true
  auto-apply = false
  terraform-version = "0.11.7"
  working-directory = "path/to/subfolder"
  vcs-repo {
    identifier = "WhatsARanjit/terraform-project"
    branch = "master"
    ingress-submodules = false
  }
  variables {
    helloworld = "foo"
    mypassword {
      value = "secret"
      sensitive = true
    }
    AWS_ACCESS_KEY {
      value = "AWS Secret Key ID"
      sensitive = true
      category = "env"
    }
    structured_data {
      value = "{ 'count': 1 }"
      hcl = true
      prefix = true
    }
    CONFIRM_DESTROY {
      value = "1"
      category = "env"
    }
  }
}
