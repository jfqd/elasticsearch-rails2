module Elasticsearch
  module Rails2

    # Contains functionality related to searching.
    #
    module Searching

      # Wraps a search request definition
      #
      class SearchRequest
        attr_reader :klass, :definition, :options

        # @param klass [Class] The class of the model
        # @param query_or_payload [String,Hash,Object] The search request definition
        #                                              (string, JSON, Hash, or object responding to `to_hash`)
        # @param options [Hash] Optional parameters to be passed to the Elasticsearch client
        #
        def initialize(klass, query_or_payload, options={})
          @klass   = klass
          @options = options

          __index_name    = options[:index] || klass.index_name
          __document_type = options[:type]  || klass.document_type

          case
            # search query: ...
            when query_or_payload.respond_to?(:to_hash)
              body = query_or_payload.to_hash

            # search '{ "query" : ... }'
            when query_or_payload.is_a?(String) && query_or_payload =~ /^\s*{/
              body = query_or_payload

            # search '...'
            else
              q = query_or_payload
          end

          if body
            @definition = { index: __index_name, type: __document_type, body: body }.update options
          else
            @definition = { index: __index_name, type: __document_type, q: q }.update options
          end
        end

        # Performs the request and returns the response from client
        #
        # @return [Hash] The response from Elasticsearch
        #
        def execute!
          klass.client.elasticsearch(@definition)
        end
      end

      module ClassMethods

        # Provides a `search` method for the model to easily search within an index/type
        # corresponding to the model settings.
        #
        # @param query_or_payload [String,Hash,Object] The search request definition
        #                                              (string, JSON, Hash, or object responding to `to_hash`)
        # @param options [Hash] Optional parameters to be passed to the Elasticsearch client
        #
        # @return [Elasticsearch::Rails2::Response]
        #
        # @example Simple search in `Article`
        #
        #     Article.elasticsearch 'foo'
        #
        # @example Search using a search definition as a Hash
        #
        #     response = Article.elasticsearch \
        #                  query: {
        #                    match: {
        #                      title: 'foo'
        #                    }
        #                  },
        #                  highlight: {
        #                    fields: {
        #                      title: {}
        #                    }
        #                  }
        #
        #     response.results.first.title
        #     # => "Foo"
        #
        #     response.results.first.highlight.title
        #     # => ["<em>Foo</em>"]
        #
        #     response.records.first.title
        #     #  Article Load (0.2ms)  SELECT "articles".* FROM "articles" WHERE "articles"."id" IN (1, 3)
        #     # => "Foo"
        #
        # @example Search using a search definition as a JSON string
        #
        #     Article.elasticsearch '{"query" : { "match_all" : {} }}'
        #
        def elasticsearch(query_or_payload, options={})
          search = SearchRequest.new(self, query_or_payload, options)
          Response::Response.new(self, search)
        end

        # Scan and scroll all ids
        # Useful to do a SQL query with IN(...) operator
        #
        def scan_all_ids(query_or_payload, options={})
          ids = []
          scroll = options[:scroll]
          search_response = search(query_or_payload, options.update(search_type: 'scan'))
          response = search_response.response
          while response = client.scroll(scroll_id: response['_scroll_id'], scroll: scroll) and !response['hits']['hits'].empty? do
            response['hits']['hits'].each { |r| ids << r['_id']}
          end
          ids
        end
      end

    end
  end
end