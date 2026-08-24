@[Link("rust_parser")]
lib LibRustParser
  fun extract_entities(raw_html : LibC::Char*, schema_json : LibC::Char*) : LibC::Char*
  fun free_json_string(ptr : LibC::Char*) : Void
  fun parser_version : LibC::Char*
end

module Kalubampa
  module Extractor
    def self.extract(raw_html : String, schema_json : String) : String?
      ptr = LibRustParser.extract_entities(raw_html.to_unsafe, schema_json.to_unsafe)
      return nil if ptr.null?

      begin
        json_str = String.new(ptr)
        json_str
      ensure
        LibRustParser.free_json_string(ptr)
      end
    end
  end
end
