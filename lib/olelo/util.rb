module Olelo
  class NotFound < NameError
    def initialize(id)
      super(:not_found.t(:id => id), id)
    end

    def status
      :not_found
    end
  end

  class MultiError < StandardError
    attr_accessor :messages

    def initialize(messages)
      @messages = messages
    end

    def message
      @messages.join(', ')
    end
  end

  module Factory
    def registry
      @registry ||= superclass.try(:registry) || {}
    end

    def register(name, klass)
      name = name.to_s
      raise(ArgumentError, "Implementation '#{name}' already exists for '#{self.name}'") if registry.key?(name)
      registry[name] = klass
    end

    def [](name)
      registry[name.to_s] || raise(NameError, "Implementation '#{name}' for '#{self.name}' not found")
    end
  end

  class BlockFile < ::File
    alias to_path path

    def each
      rewind
      while part = read(8192)
        yield part
      end
    end
  end

  module Util
    def self.included(base)
      base.extend(Util)
    end

    extend self

    def check
      errors = []
      yield(errors)
      raise MultiError, errors if !errors.empty?
    end

    # Like CGI.escape but escapes space not as +
    def escape(s)
      s = s.to_s
      s.gsub(/([^a-zA-Z0-9_.-]+)/) do
        '%' + $1.unpack('H2' * $1.bytesize).join('%').upcase
      end
    end

    # Like CGI.unescape but does not unescape +
    if ''.respond_to? :encoding
      def unescape(s)
        s = s.to_s
        enc = s.encoding
        s.gsub(/((?:%[0-9a-fA-F]{2})+)/) do
          [$1.delete('%')].pack('H*').force_encoding(enc)
        end
      end
    else
      def unescape(s)
        s.to_s.gsub(/((?:%[0-9a-fA-F]{2})+)/) do
          [$1.delete('%')].pack('H*')
        end
      end
    end

    if ''.respond_to? :encoding
      def unescape_backslash(s)
        s = s.to_s
        enc = s.encoding
        s.gsub(/\\([0-7]{3})/) { $1.to_i(8).chr.force_encoding(enc) }.
          gsub(/\\x([\da-f]{2})/i) { $1.to_i(16).chr.force_encoding(enc) }
      end
    else
      def unescape_backslash(s)
        s.to_s.gsub(/\\([0-7]{3})/) { $1.to_i(8).chr }.
          gsub(/\\x([\da-f]{2})/i) { $1.to_i(16).chr }
      end
    end

    # Escape html entities in string
    #
    # @param [String] s String
    # @return [String] Escaped string
    def escape_html(s)
      CGI.escapeHTML(s.to_s)
    end

    # Unescape html entities in string
    #
    # @param [String] s String with escaped html entities
    # @return [String] Unescaped string
    def unescape_html(s)
      CGI.unescapeHTML(s.to_s)
    end

    # Hash used by {#escape_javascript}
    # @api private
    JAVASCRIPT_ESCAPE = { '&' => '\u0026', '>' => '\u003E', '<' => '\u003C' }

    # Escape javascript code for embedding in html
    #
    # @param [String] s String
    # @return [String] Escaped string
    def escape_javascript(s)
      s.to_s.gsub(/[&><]/) { |x| JAVASCRIPT_ESCAPE[x] }
    end

    # Compute md5 hash of string
    #
    # @param [String] String
    # @return [String] md5 hash of string
    #
    def md5(s)
      Digest::MD5.hexdigest(s)
    end

    # Compute sha256 hash of string
    #
    # @param [String] String
    # @return [String] sha256 hash of string
    #
    def sha256(s)
      Digest::SHA256.hexdigest(s)
    end

    # Build query from parameter hash
    #
    # Similar to {Rack::Utils#build_query} but sorts parameters.
    # This allows the query string to be used as key for caching etc.
    #
    # @param [Hash] params Parameter hash
    # @return [String] query string
    #
    def build_query(params)
      params.map {|k,v| [k.to_s, v ] }.sort.map do |k, v|
        if v.class == Array
          build_query(v.map { |x| [k, x] })
        else
          "#{escape(k)}=#{escape(v.to_s)}"
        end
      end.join('&')
    end

    # Parse xml document string and return DOM object (Nokogiri)
    #
    # @param [String] xml document string
    # @return [Nokogiri::HTML::Document] Nokogiri Document
    def XMLDocument(xml)
      Nokogiri::HTML(xml, nil, 'UTF-8')
    end

    # Parse xml fragment and return DOM object (Nokogiri)
    #
    # @param [String] xml fragment string
    # @return [Nokogiri::HTML::DocumentFragment] Nokogiri Document Fragment
    def XMLFragment(xml)
      Nokogiri::HTML::DocumentFragment.new(XMLDocument(nil), xml)
    end

    # Creates deep copy of object by abusing `Marshal`
    # This method is slow and not adequate for huge objects.
    # It can only copy objects which are serializable.
    #
    # @param [Object] Serializable object
    # @return [Object] Deep copy of object
    def deep_copy(object)
      Marshal.load(Marshal.dump(object))
    end

    # Decode base64 encoded string
    #
    # @param [String] Base64 encoded string
    # @return [String] Decoded string
    def decode64(s)
      s.unpack('m').first
    end

    # Encode string as base64
    #
    # @param [String] String
    # @return [String] Base64 encoded string
    def encode64(s)
      [s].pack('m').gsub(/\n/, '')
    end

    # Truncate string if it is too long and add omission
    #
    # @param [String]  String to truncate
    # @param [Integer] Maximum length
    # @param [String]  Omission string, e.g. ellipsis
    # @return [String] Truncated string
    def truncate(s, max, omission = '...')
      s = s.to_s
      if s.length > max
        # Ensure that string consists only of full characters
        if !s.respond_to?(:encoding)
          max += 1 until max >= s.length || valid_xml_chars?(s[0...max])
        end
        s[0...max] + omission
      else
        s
      end
    end

    # Capitalizes all the words to create a nicer looking title
    #
    # @param [String] lowercase_string_with_underscore
    # @return [String] Lowercase String With Underscore
    def titlecase(s)
      s.to_s.tr('_', ' ').split(/\s+/).map(&:capitalize).join(' ')
    end

    # Used by {#valid_xml_chars?}
    # @api private
    VALID_XML_CHARS = [
      0x9, 0xA, 0xD,
      (0x20..0xD7FF),
      (0xE000..0xFFFD),
      (0x10000..0x10FFFF)
    ]

    if ''.respond_to?(:encoding)
      # Check if string contains only characters which are valid in XML
      #
      # @see http://www.w3.org/TR/REC-xml/#charsets XML charset
      # @param [String] s
      # @return [Boolean]
      def valid_xml_chars?(s)
        s = s.to_s
        if s.encoding == Encoding::UTF_8
          return false if !s.valid_encoding?
        else
          s = s.dup if s.frozen?
          return false if s.try_encoding(Encoding::UTF_8).encoding != Encoding::UTF_8
        end
        s.codepoints do |n|
          return false if !VALID_XML_CHARS.any? {|v| v === n }
        end
        true
      end
    else
      require 'iconv'

      # Check if string contains only characters which are valid in XML
      #
      # @see http://www.w3.org/TR/REC-xml/#charsets
      # @param [String] s
      # @return [Boolean]
      def valid_xml_chars?(s)
        s = s.to_s
        Iconv.conv('utf-8', 'utf-8', s)
        s.unpack('U*').all? {|n| VALID_XML_CHARS.any? {|v| v === n } }
      rescue
        false
      end
    end

  end
end
