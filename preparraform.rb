#!/usr/bin/env ruby
require 'rhcl'
require 'terraform-enterprise-client'

# Read YAML file with workspaces
def load_hcl(hcl)
  Rhcl.parse(File.read(hcl))
rescue StandardError
  raise %(Could not load '#{hcl}'.)
end

# Hit TFE API
def tfe_call(endpoint, verb, *data)
  puts %(#{endpoint}/#{verb}: #{data})
  res = @client.public_send(endpoint.to_sym).public_send(verb.to_sym, *data)
  raise StandardError, res.errors if res.errors?
  res.body['data']
end

# Check workspace/variable cache to see if thing exists
def obj_exists?(obj_name, type = 'workspace')
  case type
  when 'workspace'
    m = @ws_cache.select { |o| o['attributes']['name'] == obj_name }
  # Have to check variable metadata for relation to workspace
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

# Merge in workspace/org and oauth token from ENV variables
def prepare_hash(workspace, hash)
  k = @ws_id ? 'workspace' : 'name'
  h = {
    k.to_sym      => workspace,
    :organization => @organization,
  }.merge(hash)

  if h.key?(:'vcs-repo') && @oauth_token
    h[:'vcs-repo'][:'oauth-token-id'] = @oauth_token
  end

  h
end

# HCL file has no symbols
# Ruby library requires symbols in payload
def keys_to_sym(data, parent = false)
  newhash = {}
  if data.is_a?(Hash)
    if parent
      newhash = data.map do |k, v|
        # Variable names should stay as strings
        if parent == :variables
          [k.to_s, v]
        else
          [k.to_sym, v]
        end
      end
      newhash = newhash.to_h
    else
      newhash = data
    end
  end
  newhash.each do |k, v|
    newhash[k] = v.is_a?(Hash) ? keys_to_sym(v, k) : v
  end
  newhash
end

token         = ENV['TFE_TOKEN']
@organization = ENV['TFE_ORG']
@oauth_token  = ENV['TFE_OAUTH_TOKEN']
@user_prefix  = ENV['TFE_PREFIX']
@client       = TerraformEnterprise::API::Client.new(token: token)
ws_file       = ARGV[0] || './workspaces.hcl'
@ws           = keys_to_sym(load_hcl(ws_file))
@ws_id        = ''

# Cache workspace/variable list if not deleting
unless ENV['TFE_DELETE']
  @ws_cache  = tfe_call('workspaces', 'list', organization: @organization)
  @var_cache = tfe_call('variables', 'list', organization: @organization)
end

@ws.each do |workspace, configs|
  # Minimum values necessary for delete
  prefix    = configs.delete(:prefix)
  workspace = prefix(workspace) if prefix

  if ENV['TFE_DELETE']
    tfe_call(
      'workspaces',
      'delete',
      workspace: workspace,
      organization: @organization
    )
    next
  end

  # Other ops if not deleting
  @ws_id    = obj_exists?(workspace)
  variables = configs.delete(:variables)

  # Create or update depending on if workspace exists
  if @ws_id
    tfe_call(
      'workspaces',
      'update',
      prepare_hash(workspace, configs)
    )
  else
    tfe_call(
      'workspaces',
      'create',
      prepare_hash(workspace, configs)
    )
    # Set @ws_id after creating to relate variables
    @ws_id = tfe_call(
      'workspaces',
      'list',
      organization: @organization,
      name: workspace
    ).first['id']
  end

  next if variables.nil?
  variables_array = []
  variables.each do |var, data|
    variables_array <<
      # Variables can be written as a Hash or String depending on
      # if you want to use defaults
      # Hash notation showing defaults:
      # myvar:
      #   value: something
      #   sensitive: false
      #   hcl: false
      #   category: 'terraform'
      # String notation
      # myvar: something
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
