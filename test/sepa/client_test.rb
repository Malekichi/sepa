require 'test_helper'

class ClientTest < ActiveSupport::TestCase
  include Sepa::ErrorMessages

  def setup

    # Get params hashes from fixtures for different banks and for different request types
    @nordea_generic_params = nordea_generic_params
    @nordea_cert_params = nordea_cert_params
    @danske_cert_params = danske_cert_params

    # Namespaces
    @cor = 'http://bxd.fi/CorporateFileService'
  end

  test "should initialize class" do
    assert Sepa::Client.new
  end

  test "should initialize with attributes" do
    assert Sepa::Client.new @nordea_generic_params
  end

  test "should set attributes" do
    a = Sepa::Client.new
    assert a.attributes @nordea_generic_params
  end

  test "should be valid with required params" do
    sepa = Sepa::Client.new @danske_cert_params
    assert sepa.valid?, sepa.errors.messages
  end

  test "should not be valid with invalid bank" do
    @nordea_generic_params[:bank] = :royal_bank_of_skopje
    sepa = Sepa::Client.new @nordea_generic_params
    refute sepa.valid?, sepa.errors.messages
  end

  test "banks supported commands" do
    @nordea_cert_params[:bank] = :danske
    @nordea_cert_params[:command] = :get_certificate
    sepa = Sepa::Client.new @nordea_cert_params
    refute sepa.valid?, sepa.errors.messages
  end

  test "private keys are checked" do
    wrong_pks = ['Im not a key', :leppakerttu, nil]

    wrong_pks.each do |wrong_pk|
      @nordea_generic_params[:private_key] = wrong_pk
      sepa = Sepa::Client.new @nordea_generic_params
      refute sepa.valid?, sepa.errors.messages
    end
  end

  test "certificates are checked" do
    wrong_certs = ['Im not a cert', 99, :leppakerttu, nil]

    wrong_certs.each do |wrong_cert|
      @nordea_generic_params[:cert] = wrong_cert
      sepa = Sepa::Client.new @nordea_generic_params
      refute sepa.valid?, sepa.errors.messages
    end
  end

  test "customer id is correct" do
    wrong_ids = ["a"*17, nil]

    wrong_ids.each do |wrong_id|
      @nordea_generic_params[:customer_id] = wrong_id
      sepa = Sepa::Client.new @nordea_generic_params
      refute sepa.valid?, sepa.errors.messages
      assert_includes sepa.errors.messages.to_s, CUSTOMER_ID_ERROR_MESSAGE
    end
  end

  test "environment is checked" do
    wrong_envs = ["not proper", 5, :protuction]

    wrong_envs.each do |wrong_env|
      @nordea_generic_params[:environment] = wrong_env
      sepa = Sepa::Client.new @nordea_generic_params
      refute sepa.valid?, sepa.errors.messages
      assert_includes sepa.errors.messages.to_s, ENVIRONMENT_ERROR_MESSAGE
    end
  end

  test 'environment defaults to production' do
    @nordea_generic_params.delete :environment
    sepa = Sepa::Client.new @nordea_generic_params
    assert sepa.environment == 'PRODUCTION'
    assert sepa.valid?
  end

  test "status values are checked" do
    wrong_statuses = ["ready", 'steady', 5, :nipsu]

    wrong_statuses.each do |wrong_status|
      @nordea_generic_params[:command] = :download_file_list
      @nordea_generic_params[:status] = wrong_status
      sepa = Sepa::Client.new @nordea_generic_params
      refute sepa.valid?, sepa.errors.messages
    end
  end

  test "should not be valid without target id" do
    wrong_ids = ["ready"*81, nil]
    @nordea_generic_params[:command] = :upload_file

    wrong_ids.each do |wrong_id|
      @nordea_generic_params[:target_id] = wrong_id
      sepa = Sepa::Client.new @nordea_generic_params
      refute sepa.valid?, sepa.errors.messages
      assert_includes sepa.errors.messages.to_s, TARGET_ID_ERROR_MESSAGE
    end
  end

  test "language values are valid" do
    wrong_langs = ["Joo", 7, :protuction]

    wrong_langs.each do |wrong_lang|
      @nordea_generic_params[:language] = wrong_lang
      sepa = Sepa::Client.new @nordea_generic_params
      refute sepa.valid?, sepa.errors.messages
    end
  end

  test "file type is checked" do
    wrong_types = ["kalle"*36, nil]

    wrong_types.each do |wrong_type|
      [:upload_file, :download_file_list].each do |command|
        @nordea_generic_params[:command] = command
        @nordea_generic_params[:file_type] = wrong_type
        sepa = Sepa::Client.new @nordea_generic_params
        refute sepa.valid?, sepa.errors.messages
        assert_includes sepa.errors.messages.to_s, FILE_TYPE_ERROR_MESSAGE
      end
    end
  end

  test "content is required for upload file" do
    @nordea_generic_params[:command] = :upload_file
    @nordea_generic_params.delete(:content)
    sepa = Sepa::Client.new @nordea_generic_params
    refute sepa.valid?, sepa.errors.messages
    assert_includes sepa.errors.messages.to_s, CONTENT_ERROR_MESSAGE
  end

  test 'file reference is required for download file' do
    @nordea_generic_params.delete :file_reference
    sepa = Sepa::Client.new @nordea_generic_params
    refute sepa.valid?, sepa.errors.messages
    assert_includes sepa.errors.messages.to_s, FILE_REFERENCE_ERROR_MESSAGE
  end

  # # The response from savon will be the request to check that a proper request
  # # was made in the following four tests
  def test_should_send_proper_request_with_get_user_info
    @nordea_generic_params[:command] = :get_user_info
    client = Sepa::Client.new(@nordea_generic_params)
    response = client.send_request

    assert response.soap.at_css('cor|getUserInfoin', cor: @cor)

    Dir.chdir(SCHEMA_PATH) do
      xsd = Nokogiri::XML::Schema(IO.read('soap.xsd'))
      assert xsd.valid?(response.soap)
    end
  end

  def test_should_send_proper_request_with_download_file_list
    @nordea_generic_params[:command] = :download_file_list
    client = Sepa::Client.new(@nordea_generic_params)
    response = client.send_request

    assert response.soap.at_css('cor|downloadFileListin', cor: @cor)

    Dir.chdir(SCHEMA_PATH) do
      xsd = Nokogiri::XML::Schema(IO.read('soap.xsd'))
      assert xsd.valid?(response.soap)
    end
  end

  def test_should_send_proper_request_with_download_file
    @nordea_generic_params[:command] = :download_file
    client = Sepa::Client.new(@nordea_generic_params)
    response = client.send_request

    assert response.soap.at_css('cor|downloadFilein', cor: @cor)

    Dir.chdir(SCHEMA_PATH) do
      xsd = Nokogiri::XML::Schema(IO.read('soap.xsd'))
      assert xsd.valid?(response.soap)
    end
  end

  def test_should_send_proper_request_with_upload_file
    @nordea_generic_params[:command] = :upload_file
    client = Sepa::Client.new(@nordea_generic_params)
    response = client.send_request

    assert response.soap.at_css('cor|uploadFilein', cor: @cor)

    Dir.chdir(SCHEMA_PATH) do
      xsd = Nokogiri::XML::Schema(IO.read('soap.xsd'))
      assert xsd.valid?(response.soap)
    end
  end

  def test_should_initialize_with_proper_cert_params
    assert Sepa::Client.new(@nordea_cert_params)
  end

  def test_should_send_proper_request_with_get_certificate
    client = Sepa::Client.new(@nordea_cert_params)
    response = client.send_request

    assert response.soap.at_css('cer|getCertificatein')

    Dir.chdir(SCHEMA_PATH) do
      xsd = Nokogiri::XML::Schema(IO.read('soap.xsd'))
      assert xsd.valid?(response.soap)
    end
  end

  def test_should_check_signing_cert_request_with_create_certificate
    @danske_cert_params[:command] = :create_certificate
    @danske_cert_params.delete(:signing_cert_pkcs10)

    sepa = Sepa::Client.new(@danske_cert_params)
    refute sepa.valid?
    assert_includes sepa.errors.messages.to_s, SIGNING_CERT_REQUEST_ERROR_MESSAGE
  end

  def test_should_check_encryption_cert_request_with_create_certificate
    @danske_cert_params[:command] = :create_certificate
    @danske_cert_params.delete(:encryption_cert_pkcs10)

    sepa = Sepa::Client.new(@danske_cert_params)
    refute sepa.valid?
    assert_includes sepa.errors.messages.to_s, ENCRYPTION_CERT_REQUEST_ERROR_MESSAGE
  end

  def test_should_check_pin_with_create_certificate
    @danske_cert_params[:command] = :create_certificate
    @danske_cert_params.delete(:pin)

    sepa = Sepa::Client.new(@danske_cert_params)
    refute sepa.valid?
    assert_includes sepa.errors.messages.to_s, PIN_ERROR_MESSAGE
  end

  def test_should_check_encryption_cert_with_create_certificate
    @danske_cert_params[:command] = :create_certificate
    @danske_cert_params.delete(:enc_cert)

    sepa = Sepa::Client.new(@danske_cert_params)
    refute sepa.valid?
    assert_includes sepa.errors.messages.to_s, ENCRYPTION_CERT_ERROR_MESSAGE
  end

  test "response should be invalid on savon exception" do
    # Create an observer to fake sending requests to bank
    observer = Class.new {
      def notify(operation_name, builder, globals, locals)
        @operation_name = operation_name
        @builder = builder
        @globals = globals
        @locals  = locals
        HTTPI::Response.new(500, {}, 'THE ERROR!')
      end
    }.new

    Savon.observers << observer

    client = Sepa::Client.new @nordea_generic_params
    response = client.send_request

    refute response.valid?, response.errors.messages
    assert_includes response.errors.messages, "HTTP error (500): THE ERROR!"

    Savon.observers.pop
  end

end
