class McpController < ApplicationController
  include Mcp::Protocol

  disallow_account_scope
  allow_unauthenticated_access
  before_action :require_bearer_token, only: :create

  def discovery
    render json: {
      name: "Fizzy",
      description: "Kanban workflow management",
      mcp_version: Mcp::PROTOCOL_VERSION,
      capabilities: { tools: {}, resources: {} },
      oauth: { server: oauth_authorization_server_url }
    }
  end

  def create
    case jsonrpc_method
    when "initialize"       then handle_initialize
    when "tools/list"       then handle_tools_list
    when "tools/call"       then handle_tools_call
    when "resources/list"   then handle_resources_list
    when "resources/read"   then handle_resources_read
    else
      jsonrpc_error :method_not_found
    end
  rescue ActiveRecord::RecordNotFound => e
    jsonrpc_error :invalid_params, "Record not found: #{e.message}"
  rescue ActiveRecord::RecordInvalid => e
    jsonrpc_error :invalid_params, e.message
  rescue ArgumentError => e
    jsonrpc_error :invalid_params, e.message
  end

  private
    def handle_initialize
      jsonrpc_response({
        protocolVersion: Mcp::PROTOCOL_VERSION,
        capabilities: { tools: {}, resources: {} },
        serverInfo: { name: "Fizzy", title: "Fizzy Kanban", version: "1.0.0" }
      })
    end

    def handle_tools_list
      jsonrpc_response Mcp::Tools.list
    end

    def handle_tools_call
      name = jsonrpc_params[:name]
      arguments = jsonrpc_params[:arguments]&.permit!&.to_h || {}

      result = Mcp::Tools.call(name, arguments, identity: Current.identity)
      jsonrpc_response result
    end

    def handle_resources_list
      jsonrpc_response Mcp::Resources.list
    end

    def handle_resources_read
      uri = jsonrpc_params[:uri]
      result = Mcp::Resources.read(uri, identity: Current.identity)
      jsonrpc_response result
    end

    def require_bearer_token
      if token = request.authorization.to_s[/\ABearer (.+)\z/, 1]
        if identity = Identity.find_by_permissable_access_token(token, method: request.method)
          Current.identity = identity
          return
        end
      end

      response.headers["WWW-Authenticate"] = %(Bearer resource_metadata="#{oauth_protected_resource_url}")
      head :unauthorized
    end

    def oauth_protected_resource_url
      Rails.application.routes.url_helpers.url_for \
        controller: "oauth/protected_resource_metadata",
        action: "show",
        only_path: false,
        host: request.host,
        port: request.port,
        protocol: request.protocol
    end

    def oauth_authorization_server_url
      Rails.application.routes.url_helpers.url_for \
        controller: "oauth/metadata",
        action: "show",
        only_path: false,
        host: request.host,
        port: request.port,
        protocol: request.protocol
    end
end
