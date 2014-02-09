require 'open-uri'
require 'teaspoon/environment'
require 'teaspoon/export'

module Teaspoon
  class Console

    def initialize(options = {})
      @options = options
      @suites = {}
      Teaspoon::Environment.load(@options)

      @server = start_server
    rescue Teaspoon::ServerException => e
      abort(e.message)
    end

    def failures?
      !execute
    end

    def execute(options = {})
      execute_without_handling(options)
    rescue Teaspoon::Failure
      false
    rescue Teaspoon::Error => e
      abort(e.message)
    end

    def execute_without_handling(options = {})
      @options.merge!(options)
      @suites = {}
      resolve(@options[:files])

      failure_count = 0
      0 == suites.inject(0) do |failures, suite|
        export(suite) if @options.include?(:export)
        log("Teaspoon running #{suite} suite at #{url(suite)}")
        failure_count += run_specs(suite)
      end
    end

    def run_specs(suite)
      raise Teaspoon::UnknownSuite, "Unknown suite: \"#{suite}\"" unless Teaspoon.configuration.suite_configs[suite.to_s]
      log("Teaspoon running #{suite} suite at #{base_url_for(suite)}")
      runner = Teaspoon::Runner.new(suite)
      driver.run_specs(runner, url_for(suite))
      raise Teaspoon::Failure if Teaspoon.configuration.fail_fast && runner.failure_count > 0
      runner.failure_count
    end

    def export(suite)
      suite_url = url(suite)
      export_path = @options[:export] if String === @options[:export]
      exporter = Export.new(:suite => suite, :url => url(suite), :output_path => export_path)
      STDOUT.print "Teaspoon exporting #{suite} suite at #{suite_url} to #{exporter.output_path}\n" unless Teaspoon.configuration.suppress_log
      exporter.execute
    end

    protected

    def resolve(files = [])
      return if files.blank?
      files.uniq.each do |path|
        if result = Teaspoon::Suite.resolve_spec_for(path)
          suite = @suites[result[:suite]] ||= []
          suite << result[:path]
        end
      end
    end

    def start_server
      log("Starting the Teaspoon server...")
      server = Teaspoon::Server.new
      server.start
      server
    end

    def suites
      return [@options[:suite]] if @options[:suite].present?
      return @suites.keys if @suites.present?
      Teaspoon.configuration.suite_configs.keys
    end

    def driver
      return @driver if @driver
      klass = "#{Teaspoon.configuration.driver.to_s.camelize}Driver"
      @driver = Teaspoon::Drivers.const_get(klass).new(Teaspoon.configuration.driver_options)
    rescue NameError
      raise Teaspoon::UnknownDriver, "Unknown driver: \"#{Teaspoon.configuration.driver}\""
    end

    def base_url_for(suite)
      ["#{@server.url}#{Teaspoon.configuration.mount_at}", suite].join('/')
    end

    def url_for(suite)
      url = [base_url_for(suite), filter(suite)].compact.join('?')
      "#{url}#{(url.include?("?") ? "&" : "?")}reporter=Console"
    end

    def filter(suite)
      parts = []
      parts << "grep=#{URI::encode(@options[:filter])}" if @options[:filter].present?
      (@suites[suite] || @options[:files] || []).flatten.each { |file| parts << "file[]=#{URI::encode(file)}" }
      "#{parts.join('&')}" if parts.present?
    end

    def log(str, force = false)
      STDOUT.print("#{str}\n") if force || !Teaspoon.configuration.suppress_log
    end

    def abort(message = nil)
      log(message, true) if message
      exit(1)
    end
  end
end
