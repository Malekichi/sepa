require 'test_helper'

class TestSepa < ActiveSupport::TestCase
  test 'version is defined correctly' do
    refute_nil Sepa::VERSION
    assert_equal '1.1.9.1', Sepa::VERSION
  end
end
