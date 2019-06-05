#
# Copyright 2012-2018 Chef Software, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require "fileutils"
require "omnibus/download_helpers"

module Omnibus
  class ArtifactoryFetcher < NetFetcher
    private

    #
    # A find_url is required if the search in artifactory is required to find its file name
    #
    # @return [String]
    #
    def find_source_url
      require 'base64'
      require("digest")
      require("artifactory")

      log.info(:info) { "Searching Artifactory for #{source[:pattern]} in #{source[:repository]} " }

      endpoint = source[:endpoint] || ENV['ARTIFACTORY_ENDPOINT'] || nil
      raise 'Artifactory endpoint not configured' if endpoint.nil?

      Artifactory.endpoint = endpoint
      Artifactory.api_key  = source[:authorization ] if source[:authorization]

      unless source.key?(:authorization)
        username = ENV['ARTIFACTORY_USERNAME'] || nil
        password = ENV['ARTIFACTORY_PASSWORD'] || nil
        error_message = "You have to provide either source[:authorization] or environment variables for artifactory client"
        raise error_message if username.nil? || password.nil?

        source[:authorization] = "Basic #{Base64.encode64("#{username}:#{password}")}"
      end

      log.debug(:debug) { "Path to file #{source[:path]} in #{source[:repository]}" }

      result = Artifactory::Resource::Artifact.search(name: source[:filename_pattern], repos: source[:repository])
      raise "Unable to find #{source[:filename_pattern]} in #{source[:repository]}" if result.nil? || result.empty?

      if result.kind_of?(Array)
        result.select! do |item|
          uri_without_filename = item.download_uri.split('/')[0..-2].join('/')
          uri_without_filename.start_with?("#{endpoint}/#{source[:repository]}#{source[:path]}")
        end
        raise "Unable to find #{source[:filename_pattern]} in #{source[:repository]} with path #{source[:path]}" if result.empty?

        result.sort_by!(&:created)
        artifact = result[-1]
      else
        artifact = result
      end
      log.debug(:debug) { "Found Artifact #{artifact.inspect}" }
      log.info(:info) { "Found Artifact #{artifact.download_uri} #{artifact.checksums['sha1']}" }

      source[:url] = artifact.download_uri
      source[:sha1] = artifact.checksums['sha1']
    end

    #
    # The path on disk to the downloaded asset. The filename is defined by
    # +source :cached_name+. If ommited, then it comes from the search artifacts url from artifactory
    # +source :path+ value
    #
    # @return [String]
    #
    def downloaded_file
      unless source.key?(:url)
        find_source_url
      end

      filename = source[:cached_name] if source[:cached_name]
      filename ||= File.basename(source[:url], "?*")
      File.join(Config.cache_dir, filename)
    end
  end
end
