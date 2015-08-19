module Content
  module Strategies
    module Direct
      class Book < Entity

        wraps ::Content::Models::Book

        exposes :ecosystem, :chapters, :pages, :url, :uuid, :version, :cnx_id, :title

        alias_method :entity_ecosystem, :ecosystem
        def ecosystem
          ::Content::Ecosystem.new(strategy: entity_ecosystem)
        end

        alias_method :entity_chapters, :chapters
        def chapters
          entity_chapters.collect do |entity_chapter|
            ::Content::Chapter.new(strategy: entity_chapter)
          end
        end

        alias_method :entity_pages, :pages
        def pages
          entity_pages.collect do |entity_page|
            ::Content::Page.new(strategy: entity_page)
          end
        end

        alias_method :string_uuid, :uuid
        def uuid
          ::Content::Uuid.new(string_uuid)
        end

      end
    end
  end
end