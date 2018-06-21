# Preparraform [![Build Status](https://travis-ci.org/WhatsARanjit/terraform-preparraform.svg?branch=hcl)](https://travis-ci.org/WhatsARanjit/terraform-preparraform)

#### Table of Contents

1. [Overview](#overview)
1. [Setup](#setup)
1. [Usage](#usage)


## Overview

Create and destroy workspaces from a template.

## Setup

Install the gems in the `Gemfile` using your favorite Ruby environment.
Next you will have to configure a few environment variables.

* `TFE_TOKEN`

Authentication token for TFE user.

* `TFE_ORG`

The name of the organization you would like to manage.

* `TFE_OAUTH_TOKEN`

The OAuth token that can be used.  This can be found from `tfe oauth_tokens list --organization=$TFE_ORG --only=id --value`.

* `TFE_PREFIX`

This can be used to prefix the workspace name and/or variables/values within the workspace (optional).

## Usage

Follow the example in `workspaces.hcl`.  Generally using `prefix = true` anywhere will use the prefix you've given in the environment variable in the format `$prefix_$value`.  All options are shown in the sample.

Terraform variables can be specified as `var = "value"` for simple variables.  In order to specify, environment variables, `hcl` or `sensitive`, or use prefixing, an HCL block must be used.  Then run using

```
./preparraform.rb
```

By default, it will look for a file called `workspaces.hcl` in your current working directory.  An alternate file can be specified as an argument:

```
./preparraform.rb path/to/another/file.hcl
```

Workspaces can be deleted by setting a `TFE_DELETE` environment variable to any value.
