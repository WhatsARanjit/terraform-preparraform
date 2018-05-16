#!/usr/bin/env ruby
require 'yaml'
require 'terraform-enterprise-client'

def load_yaml(yaml = './workspaces.yaml')
  YAML.load_file(yaml)
rescue StandardError
  raise %(Could not load '#{yaml}'.)
end

def tfe_call(endpoint, verb, *data)
  res = @client.public_send(endpoint.to_sym).public_send(verb.to_sym, *data)
  raise StandardError, res.errors if res.errors?
  puts %(#{endpoint}/#{verb}: #{data})
  res.body['data']
end

def obj_exists?(obj_name, type = 'workspace')
  case type
  when 'workspace'
    m = @ws_cache.select { |o| o['attributes']['name'] == obj_name }
  when 'variable'
    m = @var_cache.select do |o|
      o['attributes']['key'] == obj_name &&
        o['relationships']['configurable']['data']['id'] == @ws_id
    end
  end

  if m.count == 1
    m.first['id']
  elsif m.count.zero?
    false
  else # something is wrong
    raise StandError, %(More than one object matches the name '#{obj_name}'!)
  end
end

def sensitive?(id)
  m = @var_cache.select { |v| v['id'] == id }
  m.first['attributes']['sensitive'] || false
end

def prefix(value)
  @user_prefix ? %(#{@user_prefix}_#{value}) : value
end

token         = ENV['TFE_TOKEN']
@organization = ENV['TFE_ORG']
@oauth_token  = ENV['TFE_OAUTH_TOKEN']
@user_prefix  = ENV['TFE_PREFIX']
@client       = TerraformEnterprise::API::Client.new(token: token)
@ws_cache     = tfe_call('workspaces', 'list', organization: @organization)
@var_cache    = tfe_call('variables', 'list', organization: @organization)
@ws           = load_yaml
@ws_id        = ''

@ws.each do |workspace, configs|
  prefix    = configs.delete(:prefix)
  workspace = prefix(workspace) if prefix
  @ws_id    = obj_exists?(workspace)
  variables = configs.delete(:variables)

  if ENV['TFE_DELETE']
    tfe_call(
      'workspaces',
      'delete',
      workspace: workspace,
      organization: @organization
    )
    next
  end

  if @ws_id
    tfe_call(
      'workspaces',
      'update',
      {
        workspace: workspace,
        organization: @organization,
        :'vcs-repo' => { :'oauth-token-id' => @oauth_token }
      }.merge(configs)
    )
  else
    tfe_call(
      'workspaces',
      'create',
      {
        name: workspace,
        organization: @organization,
        :'vcs-repo' => { :'oauth-token-id' => @oauth_token }
      }.merge(configs)
    )
    @ws_id = tfe_call(
      'workspaces',
      'list',
      organization: @organization,
      name: workspace
    ).first['id']
  end

  next if variables.empty?
  variables_array = []
  variables.each do |var, data|
    variables_array <<
      case data
      when Hash
        prefix = data.delete(:prefix)
        var    = prefix ? prefix(var) : var
        {
          key: var,
          category: 'terraform',
        }.merge(data)
      else
        {
          key: var,
          value: data,
          category: 'terraform',
        }
      end
  end
  variables_array.each do |vardata|
    id = obj_exists?(vardata[:key], 'variable')

    if id
      # Need to delete and recreate variables when sensitive
      if sensitive?(id)
        tfe_call(
          'variables',
          'delete',
          id: id
        )
        tfe_call(
          'variables',
          'create',
          vardata.merge(
            workspace: workspace,
            organization: @organization
          )
        )
      else
        tfe_call(
          'variables',
          'update',
          vardata.merge(
            id: id
          )
        )
      end
    else
      tfe_call(
        'variables',
        'create',
        vardata.merge(
          workspace: workspace,
          organization: @organization
        )
      )
    end
  end
end
