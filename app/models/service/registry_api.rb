module Service
  class RegistryApi
    DOCKER_HUB = 'https://index.docker.io/'.freeze
    DEFAULTS = {
      url: 'http://localhost:5000'.freeze,
      connection: { omit_default_port: true,
                    headers: { "Content-Type" => "application/json" }}
    }

    attr_accessor :config, :url
    delegate :logger, :to => Rails

    def initialize(params = {})
      self.config = DEFAULTS.merge(params)
      self.url = config[:url]

      Docker.logger = logger if Rails.env.development? || Rails.env.test?
    end

    def connection
      @connection ||= ::Docker::Connection.new(url, default_connection_options.merge(credentials))
    end

    def get(path, params = nil)
      response = connection.get('/'.freeze, params,
                                connection.options.merge({ path: "#{path}" }))
      response = parse_json(response)
      response
    end

    # Since the Registry API v2 does not support a search the v1 endpoint is used
    # Newer registries will fail, the v2 catalog endpoint is used
    def search(query)
      get('/v1/search'.freeze, { q: query })
    rescue => e
      logger.warn "API v1 - Search failed #{e.backtrace}"
      { 'results' => catalog(query) }
    end

    # Some Registries might have this endpoint not implemented/enabled
    def catalog(query)
      get('/v2/_catalog'.freeze)['repositories'].select do |image|
        image =~ /^#{query}/
      end.map { |image_name| { 'name' => image_name } }
    end

    def tags(image_name, query = nil)
      result = get_tags(image_name)
      result = result.keys.map { |t| {'name' => t.to_s } } if result.is_a? Hash
      result = filter_tags(result, query) if query
      result
    end

    def ok?
      get('/v1/'.freeze).match("Docker Registry API")
    rescue => e
      logger.warn "API v1 - Ping failed #{e.backtrace}"
      get('/v2/'.freeze).is_a? Hash
    end

    def self.docker_hub
      @@docker_hub ||= new(url: DOCKER_HUB)
    end

    private

    def default_connection_options
      @default_connection_options ||= DEFAULTS[:connection].tap do |defaults|
        defaults[:ssl_verify_peer] = config.fetch(:verify_ssl, true)
      end
    end

    def parse_json(string)
      JSON.parse(string)
    rescue => e
      logger.warn "JSON parsing failed: #{e.backtrace}"
      string
    end

    def get_tags(image_name)
      get("/v1/repositories/#{image_name}/tags")
    rescue => e
      logger.warn "API v1 - Repository images request failed #{e.backtrace}"
      tags_v2(image_name)
    end

    def tags_v2(image_name)
      get("/v2/#{image_name}/tags/list")['tags'].map { |tag| { 'name' => tag } }
    rescue Docker::Error::NotFoundError
      []
    end

    def credentials
      { user: config.fetch(:user, nil),
        password: config.fetch(:password, nil) }
    end

    def filter_tags(result, query)
      result.select do |tag_name|
        tag_name['name'] =~ /^#{query}/
      end
    end
  end
end
