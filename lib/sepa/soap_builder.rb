module Sepa
  # Builds a soap message with given parameters. This class is extended with proper bank module
  # depending on bank.
  class SoapBuilder
    include Utilities

    # Application request built with the same parameters as the soap
    #
    # @return [ApplicationRequest]
    attr_reader :application_request

    # Initializes the {SoapBuilder} with the params hash and then extends the {SoapBuilder} with the
    # correct bank module. The {SoapBuilder} class is usually created by the client which handles
    # parameter validation.
    #
    # @param params [Hash] options hash
    def initialize(params)
      @bank                        = params[:bank]
      @own_signing_certificate     = params[:own_signing_certificate]
      @command                     = params[:command]
      @content                     = params[:content]
      @customer_id                 = params[:customer_id]
      @bank_encryption_certificate = params[:bank_encryption_certificate]
      @environment                 = params[:environment]
      @file_reference              = params[:file_reference]
      @file_type                   = params[:file_type]
      @language                    = params[:language]
      @signing_private_key         = params[:signing_private_key]
      @status                      = params[:status]
      @target_id                   = params[:target_id]
      @channel_type                = params[:channel_type]

      find_correct_bank_extension

      @application_request         = ApplicationRequest.new(params.merge(digest_method: digest_method))
      @header_template             = load_header_template
      @template                    = load_body_template SOAP_TEMPLATE_PATH
    end

    # Returns the soap as raw xml
    #
    # @return [String] the soap as xml
    def to_xml
      find_correct_build.to_xml
    end

    private

      # Extends the class with proper module depending on bank
      def find_correct_bank_extension
        extend("Sepa::#{@bank.capitalize}SoapRequest".constantize)
      end

      # Determines which soap request to build based on command. Certificate requests are built
      # differently than generic requests.
      #
      # @return [Nokogiri::XML] the soap as a nokogiri document
      def find_correct_build
        STANDARD_COMMANDS.include?(@command) ? build_common_request : build_certificate_request
      end

      # Builds generic request which is a request made with commands:
      # * Get User Info
      # * Download File
      # * Download File List
      # * Upload File
      #
      # @return [Nokogiri::XML] the generic request soap
      def build_common_request
        common_set_body_contents
        set_receiver_id
        process_header
        add_body_to_header
      end

      # Sets contents for certificate request
      #
      # @return [Nokogiri::XML] the template with contents added to it
      def build_certificate_request
        set_body_contents
      end

      # Sets soap body contents. Application request is base64 encoded here.
      #
      # @return [Nokogiri::XML] the soap with contents added to it
      def set_body_contents
        set_node @template, "ApplicationRequest", @application_request.to_base64, namespace: cert_ns
        set_node @template, "SenderId",           @customer_id,                   namespace: cert_ns
        set_node @template, "RequestId",          request_id,                     namespace: cert_ns
        set_node @template, "Timestamp",          iso_time,                       namespace: cert_ns

        @template
      end

      # Loads soap header template to be later populated
      #
      # @return [Nokogiri::XML] the header as Nokogiri document
      def load_header_template
        path = File.open("#{SOAP_TEMPLATE_PATH}/header.xml")
        Nokogiri::XML(path)
      end

      # Sets value to a node's content in the given document
      # @param doc [Nokogiri::XML] The document that contains the node
      # @param node [String] The name of the node which value is about to be set
      # @param value [#to_s] The value which will be set to the node
      def set_node(doc, node, value, namespace: nil)
        if namespace
          doc.at("xmlns|#{node}", xmlns: namespace).content = value
        else
          doc.at(node).content = value
        end
      end

      # Adds soap body to header template
      #
      # @return [Nokogiri::XML] the soap with added body as a nokogiri document
      def add_body_to_header
        body = @template.at_css('env|Body')
        @header_template.root.add_child(body)
        @header_template
      end

      # Add needed information to soap header. Mainly security related stuff. The process is as
      # follows:
      # 1. The reference id of the security token is set using {#set_token_id} method
      # 2. Created and expires timestamps are set. Expires is set to be 5 minutes after creation.
      # 3. Timestamp reference id is set with {#set_node_id} method
      # 4. The digest of timestamp node is calculated and set to correct node
      # 5. The reference id of body is set with {#set_node_id}
      # 6. The digest of body is calculated and set to correct node
      # 7. The signature of SignedInfo node is calculated and added to correct node
      # 8. Own signing certificate is formatted (Begin and end certificate removed and linebreaks
      #    removed) and embedded in the soap
      # @todo split into smaller methods
      def process_header
        set_token_id

        set_node(@header_template, 'wsu|Created', iso_time)
        set_node(@header_template, 'wsu|Expires', (Time.now.utc + 300).iso8601)

        timestamp_id = set_node_id(@header_template, OASIS_UTILITY, 'Timestamp', 0)

        @header_template.css('dsig|DigestMethod').each do |node|
          node['Algorithm'] = digest_method == :sha256 ? 'http://www.w3.org/2001/04/xmlenc#sha256' : 'http://www.w3.org/2000/09/xmldsig#sha1'
        end

        timestamp_digest = calculate_digest(@header_template.at_css('wsu|Timestamp'), digest_method: digest_method)
        dsig = "dsig|Reference[URI='##{timestamp_id}'] dsig|DigestValue"
        set_node(@header_template, dsig, timestamp_digest)

        body_id = set_node_id(@template, ENVELOPE, 'Body', 1)

        body_digest = calculate_digest(@template.at_css('env|Body'), digest_method: digest_method)
        dsig = "dsig|Reference[URI='##{body_id}'] dsig|DigestValue"
        set_node(@header_template, dsig, body_digest)

        @header_template.css('dsig|SignatureMethod').each do |node|
          node['Algorithm'] = digest_method == :sha256 ? 'http://www.w3.org/2001/04/xmldsig-more#rsa-sha256' : 'http://www.w3.org/2000/09/xmldsig#rsa-sha1'
        end

        signature = calculate_signature(@header_template.at_css('dsig|SignedInfo'), digest_method: digest_method)
        set_node(@header_template, 'dsig|SignatureValue', signature)

        formatted_cert = format_cert(@own_signing_certificate)
        set_node(@header_template, 'wsse|BinarySecurityToken', formatted_cert)
      end

      # Generates a random token id and sets it to correct node
      def set_token_id
        security_token_id = "token-#{SecureRandom.uuid}"

        @header_template.at('wsse|BinarySecurityToken')['wsu:Id'] = security_token_id
        @header_template.at('wsse|Reference')['URI'] = "##{security_token_id}"
      end

      # Generates a random request id
      #
      # @return [String] hexnumeric request id
      def request_id
        SecureRandom.hex(17)
      end

      # Sets nodes for generic requests, application request is base64 encoded here.
      def common_set_body_contents
        set_application_request
        set_node @template, 'bxd|SenderId',           @customer_id
        set_node @template, 'bxd|RequestId',          request_id
        set_node @template, 'bxd|Timestamp',          iso_time
        set_node @template, 'bxd|Language',           @language
        set_node @template, 'bxd|UserAgent',          "Sepa Transfer Library version #{VERSION}"
      end

      def set_application_request
        set_node @template, 'bxd|ApplicationRequest', @application_request.to_base64
      end

      def digest_method
        :sha1
      end
  end
end
