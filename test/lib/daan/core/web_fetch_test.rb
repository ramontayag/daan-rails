require 'test_helper'

class WebFetchTest < ActiveSupport::TestCase
  def setup
    @tool = Daan::Core::WebFetch.new
  end

  def test_validates_url_format
    assert_raises(ArgumentError, "Invalid URL format") do
      @tool.execute(url: "not-a-url")
    end
    
    assert_raises(ArgumentError, "Invalid URL format") do
      @tool.execute(url: "ftp://example.com")
    end
  end

  def test_accepts_valid_urls
    # Note: These tests would need VCR cassettes or mocking in a real implementation
    # For now, we're just testing the URL validation logic
    
    # This would normally make a real request, but we'll skip for unit testing
    skip "Integration test - requires actual web request or mocking"
    
    result = @tool.execute(url: "https://example.com")
    assert_kind_of String, result
    assert_includes result, "<html"
  end

  def test_timeout_parameter
    # Test that timeout parameter is accepted
    skip "Integration test - requires actual web request or mocking"
    
    assert_nothing_raised do
      @tool.execute(url: "https://example.com", timeout: 5)
    end
  end

  def test_wait_for_selector_parameter
    # Test that wait_for_selector parameter is accepted
    skip "Integration test - requires actual web request or mocking"
    
    assert_nothing_raised do
      @tool.execute(url: "https://example.com", wait_for_selector: "body")
    end
  end

  private

  def test_url_validation_private_method
    tool = Daan::Core::WebFetch.new
    
    # Test valid URLs
    assert_nothing_raised do
      tool.send(:validate_url, "https://example.com")
    end
    
    assert_nothing_raised do
      tool.send(:validate_url, "http://example.com")
    end
    
    # Test invalid URLs
    assert_raises(ArgumentError) do
      tool.send(:validate_url, "not-a-url")
    end
    
    assert_raises(ArgumentError) do
      tool.send(:validate_url, "ftp://example.com")
    end
  end
end