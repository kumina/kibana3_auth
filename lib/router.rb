require 'rack'
require 'login'
require 'es_proxy'
require 'kibana'

class Router
	include Helpers

	LOGSTASH_INDEX     = %r{(logstash-[\d\.]{10})}
	LOGSTASH_INDICES   = %r{(?:#{LOGSTASH_INDEX},?)+}

	SEARCH_PATH        = %r{\A/#{LOGSTASH_INDICES}/_search/*?\z}
	INDEX_ALIASES_PATH = %r{\A/#{LOGSTASH_INDICES}/_aliases\z}
	MAPPING_PATH       = %r{\A/#{LOGSTASH_INDICES}/_mapping/field/\*?\z}
	NODES_PATH         = %r{\A/_nodes/?\z}
	ALIASES_PATH       = %r{\A/_aliases/*?\z}
	KIBANA_DB_PATH     = %r{\A/kibana-int/dashboard/}

	ES_PATHS = Regexp.union(SEARCH_PATH, INDEX_ALIASES_PATH,
		MAPPING_PATH, NODES_PATH, ALIASES_PATH, KIBANA_DB_PATH)

	# Evaluated in order, from top to bottom.
	URL_MAP = [
		[%r{\A/(?:logout|login)/*?\z}, :upstream_login ]         ,
		[ES_PATHS                    , :upstream_elastic_search] ,
		[//                          , :upstream_kibana]         ,
	]

	attr_reader :upstream_kibana, :upstream_login, :upstream_elastic_search

	def initialize(config)
		@config = config

		@upstream_kibana = ::Kibana.new
		@upstream_login = ::Login.new(config)
		@upstream_elastic_search = ::ESProxy.new(config)
	end

	def call(env)
		# No access for you! Unless you have the secret session.
		# Or of course, you are asking for '/login', exactly.
		unless env['rack.session'][:logged_in] then
			if env['PATH_INFO'] == '/login'
				return self.upstream_login.call(env)
			end
			response = ::Rack::Response.new
			response.redirect('/login')
			return response.finish
		end


		URL_MAP.each do |pattern, sym|
			if env['PATH_INFO'] =~ pattern then
				# Stop at the first match
				return self.send(sym).call(env)
			end
		end
	end
end
